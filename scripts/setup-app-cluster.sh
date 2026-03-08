#!/bin/bash
# =============================================================================
# setup-app-cluster.sh
# Prépare le cluster infra_app pour l'intégration Vault Kubernetes Auth
#
# Ce script s'exécute sur le master du cluster infra_app (en SSH ou directement).
# Il requiert sudo pour modifier /etc/systemd/system/k3s.service.
#
# Usage: ./setup-app-cluster.sh --config /path/to/config-app.json
#
# Actions :
#   1. Vérifie si --tls-san est déjà dans k3s.service
#   2. Modifie k3s.service pour ajouter --tls-san=<floating_ip>
#   3. Supprime les anciens certs kube-apiserver et redémarre K3s
#   4. Vérifie que le SAN est bien présent dans le nouveau certificat
#   5. Crée le ServiceAccount vault-auth + ClusterRoleBinding
#   6. Génère le JWT du SA vault-auth
#   7. Crée le ServiceAccount app-sa
#   8. Exporte le CA cert
#   9. Génère un fichier JSON avec les valeurs pour le script Vault
#
# Dépendances : jq, kubectl, openssl, sudo
# =============================================================================

set -euo pipefail

# --- Couleurs ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${BLUE}>>> $*${NC}"; }

# =============================================================================
# USAGE
# =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") --config <fichier.json> [OPTIONS]

Options:
  --config      Chemin vers le fichier de configuration JSON (obligatoire)
  --dry-run     Affiche les actions sans les exécuter
  --skip-k3s    Ne modifie pas k3s.service (si TLS SAN déjà configuré)
  --help        Affiche cette aide

Exemple:
  $(basename "$0") --config scripts/config-app.json

Ce script doit être exécuté sur le master infra_app avec sudo disponible.
Pour exécuter depuis ta machine locale via SSH :
  ssh user@<APP_MASTER_IP> "bash -s" < scripts/setup-app-cluster.sh -- --config /tmp/config-app.json
EOF
  exit 0
}

# =============================================================================
# PARSING DES ARGUMENTS
# =============================================================================
CONFIG_FILE=""
DRY_RUN=false
SKIP_K3S=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)    CONFIG_FILE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true;     shift   ;;
    --skip-k3s)  SKIP_K3S=true;    shift   ;;
    --help)      usage ;;
    *) log_error "Argument inconnu : $1"; usage ;;
  esac
done

# =============================================================================
# VALIDATION CONFIG
# =============================================================================
validate_config() {
  if [[ -z "$CONFIG_FILE" ]]; then
    log_error "--config est obligatoire."
    usage
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Fichier de config introuvable : $CONFIG_FILE"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "'jq' est requis. Installer : apt install jq"
    exit 1
  fi

  if ! command -v kubectl &>/dev/null; then
    log_error "'kubectl' non trouvé dans PATH."
    exit 1
  fi

  if ! command -v openssl &>/dev/null; then
    log_error "'openssl' non trouvé dans PATH."
    exit 1
  fi

  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log_error "Fichier JSON invalide : $CONFIG_FILE"
    exit 1
  fi

  log_success "Fichier de config valide : $CONFIG_FILE"
}

# =============================================================================
# LECTURE CONFIG
# =============================================================================
load_config() {
  FLOATING_IP=$(jq -r '.floating_ip' "$CONFIG_FILE")

  NAMESPACE=$(jq -r '.kubernetes.namespace         // "default"'        "$CONFIG_FILE")
  SA_REVIEWER=$(jq -r '.kubernetes.sa_token_reviewer // "vault-auth"'   "$CONFIG_FILE")
  SA_REVIEWER_BINDING=$(jq -r '.kubernetes.sa_token_reviewer_binding // "vault-auth-binding"' "$CONFIG_FILE")
  SA_APP=$(jq -r '.kubernetes.sa_app               // "app-sa"'         "$CONFIG_FILE")
  JWT_DURATION=$(jq -r '.kubernetes.jwt_duration   // "87600h"'         "$CONFIG_FILE")

  K3S_SERVICE=$(jq -r '.k3s.service_file           // "/etc/systemd/system/k3s.service"'                          "$CONFIG_FILE")
  CA_CERT_PATH=$(jq -r '.k3s.ca_cert_path          // "/var/lib/rancher/k3s/server/tls/server-ca.crt"'            "$CONFIG_FILE")
  APISERVER_CERT=$(jq -r '.k3s.apiserver_cert_path // "/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt"' "$CONFIG_FILE")
  APISERVER_KEY=$(jq -r '.k3s.apiserver_key_path   // "/var/lib/rancher/k3s/server/tls/serving-kube-apiserver.key"' "$CONFIG_FILE")
  RESTART_WAIT=$(jq -r '.k3s.restart_wait_seconds  // "25"'             "$CONFIG_FILE")

  CA_LOCAL_PATH=$(jq -r '.output.ca_cert_local_path      // "/tmp/app-cluster-ca.crt"'       "$CONFIG_FILE")
  VAULT_OUTPUT=$(jq -r '.output.vault_config_output       // "/tmp/vault-config-values.json"' "$CONFIG_FILE")

  # Validation des champs obligatoires
  local errors=0
  if [[ -z "$FLOATING_IP" || "$FLOATING_IP" == "null" ]]; then
    log_error "Champ manquant : floating_ip"
    errors=$((errors + 1))
  fi
  [[ $errors -gt 0 ]] && { log_error "Erreur(s) dans la config. Arrêt."; exit 1; }

  log_success "Configuration chargée"
  log_info "  Floating IP         : $FLOATING_IP"
  log_info "  Namespace           : $NAMESPACE"
  log_info "  SA token reviewer   : $SA_REVIEWER"
  log_info "  SA app              : $SA_APP"
  log_info "  JWT duration        : $JWT_DURATION"
  log_info "  K3s service file    : $K3S_SERVICE"
  log_info "  CA cert path        : $CA_CERT_PATH"
  log_info "  CA local output     : $CA_LOCAL_PATH"
  log_info "  Vault config output : $VAULT_OUTPUT"
}

# =============================================================================
# ÉTAPE 1 : VÉRIFICATION DU TLS SAN ACTUEL
# =============================================================================
check_tls_san() {
  log_step "Étape 1 : Vérification du TLS SAN actuel"

  if [[ ! -f "$APISERVER_CERT" ]]; then
    log_warn "Certificat kube-apiserver introuvable (sera généré après redémarrage K3s)."
    return 0
  fi

  local san_output
  san_output=$(sudo openssl x509 -in "$APISERVER_CERT" -noout -text 2>/dev/null | grep -A5 "Subject Alternative Name" || true)

  if echo "$san_output" | grep -q "$FLOATING_IP"; then
    log_success "IP $FLOATING_IP déjà présente dans le SAN du certificat."
    if [[ "$SKIP_K3S" == false ]]; then
      log_warn "Passer --skip-k3s pour éviter de modifier k3s.service inutilement."
    fi
  else
    log_warn "IP $FLOATING_IP absente du SAN. Modification de k3s.service nécessaire."
    log_info "SAN actuel : $san_output"
  fi
}

# =============================================================================
# ÉTAPE 2 : MODIFIER k3s.service POUR AJOUTER --tls-san
# =============================================================================
patch_k3s_service() {
  if [[ "$SKIP_K3S" == true ]]; then
    log_step "Étape 2 : Modification k3s.service (SKIP)"
    log_warn "--skip-k3s actif, k3s.service non modifié."
    return 0
  fi

  log_step "Étape 2 : Modification de $K3S_SERVICE"

  if [[ ! -f "$K3S_SERVICE" ]]; then
    log_error "Fichier introuvable : $K3S_SERVICE"
    exit 1
  fi

  # Vérifie si --tls-san est déjà présent avec cette IP
  if sudo grep -q -- "--tls-san=${FLOATING_IP}" "$K3S_SERVICE"; then
    log_warn "--tls-san=${FLOATING_IP} déjà présent dans $K3S_SERVICE, skip modification."
    return 0
  fi

  log_info "Sauvegarde de $K3S_SERVICE → ${K3S_SERVICE}.bak"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] cp $K3S_SERVICE ${K3S_SERVICE}.bak"
    log_warn "[DRY-RUN] Ajout de --tls-san=${FLOATING_IP} dans ExecStart"
    return 0
  fi

  sudo cp "$K3S_SERVICE" "${K3S_SERVICE}.bak"

  # Stratégie : si "server \" existe déjà dans ExecStart, ajouter --tls-san après
  # Sinon, remplacer "server$" par "server \ \n    --tls-san=IP"
  if sudo grep -qP '^\s+server\s*\\?\s*$' "$K3S_SERVICE"; then
    # "server \" déjà sur sa propre ligne : insérer --tls-san après
    sudo sed -i "/^\s*server\s*\\\\/a\\    --tls-san=${FLOATING_IP}" "$K3S_SERVICE"
  elif sudo grep -q 'server$' "$K3S_SERVICE"; then
    # "server" en fin de ligne sans backslash : ajouter backslash et --tls-san
    sudo sed -i "s|server$|server \\\\\n    --tls-san=${FLOATING_IP}|" "$K3S_SERVICE"
  else
    log_error "Impossible de localiser 'server' dans ExecStart de $K3S_SERVICE."
    log_error "Modifier le fichier manuellement et relancer avec --skip-k3s."
    exit 1
  fi

  log_success "k3s.service modifié (backup : ${K3S_SERVICE}.bak)"
  log_info "Contenu ExecStart après modification :"
  sudo grep -A5 "ExecStart" "$K3S_SERVICE" || true
}

# =============================================================================
# ÉTAPE 3 : SUPPRIMER LES ANCIENS CERTS ET REDÉMARRER K3s
# =============================================================================
restart_k3s() {
  if [[ "$SKIP_K3S" == true ]]; then
    log_step "Étape 3 : Redémarrage K3s (SKIP)"
    log_warn "--skip-k3s actif, K3s non redémarré."
    return 0
  fi

  log_step "Étape 3 : Suppression des anciens certs et redémarrage K3s"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] sudo rm -f $APISERVER_CERT $APISERVER_KEY"
    log_warn "[DRY-RUN] sudo systemctl daemon-reload"
    log_warn "[DRY-RUN] sudo systemctl restart k3s"
    log_warn "[DRY-RUN] sleep ${RESTART_WAIT}s"
    return 0
  fi

  log_info "Suppression des anciens certificats kube-apiserver..."
  sudo rm -f "$APISERVER_CERT" "$APISERVER_KEY"
  log_success "Anciens certificats supprimés"

  log_info "Rechargement systemd..."
  sudo systemctl daemon-reload

  log_info "Redémarrage K3s..."
  sudo systemctl restart k3s

  log_info "Attente de la régénération des certificats (${RESTART_WAIT}s)..."
  sleep "$RESTART_WAIT"

  # Vérification que K3s est bien reparti
  if ! sudo systemctl is-active --quiet k3s; then
    log_error "K3s n'est pas actif après redémarrage."
    sudo systemctl status k3s --no-pager || true
    exit 1
  fi

  log_success "K3s redémarré et actif"
}

# =============================================================================
# ÉTAPE 4 : VÉRIFIER LE TLS SAN POST-RESTART
# =============================================================================
verify_tls_san() {
  if [[ "$SKIP_K3S" == true ]]; then
    log_step "Étape 4 : Vérification TLS SAN (SKIP)"
    return 0
  fi

  log_step "Étape 4 : Vérification du TLS SAN dans le nouveau certificat"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] openssl x509 -in $APISERVER_CERT -noout -text | grep SAN"
    return 0
  fi

  local max_wait=60
  local waited=0
  while [[ ! -f "$APISERVER_CERT" && $waited -lt $max_wait ]]; do
    log_info "Attente du certificat ($waited/${max_wait}s)..."
    sleep 5
    waited=$((waited + 5))
  done

  if [[ ! -f "$APISERVER_CERT" ]]; then
    log_error "Certificat non régénéré après ${max_wait}s : $APISERVER_CERT"
    exit 1
  fi

  local san_output
  san_output=$(sudo openssl x509 -in "$APISERVER_CERT" -noout -text 2>/dev/null | grep -A5 "Subject Alternative Name" || true)
  log_info "SAN du nouveau certificat :"
  echo "$san_output"

  if echo "$san_output" | grep -q "$FLOATING_IP"; then
    log_success "IP $FLOATING_IP présente dans le SAN ✓"
  else
    log_error "IP $FLOATING_IP ABSENTE du SAN ! Vérifier la modification de k3s.service."
    exit 1
  fi
}

# =============================================================================
# ÉTAPE 5 : CRÉER LE SERVICEACCOUNT vault-auth
# =============================================================================
create_sa_vault_auth() {
  log_step "Étape 5 : ServiceAccount '$SA_REVIEWER' (namespace: $NAMESPACE)"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] kubectl create serviceaccount $SA_REVIEWER -n $NAMESPACE"
    log_warn "[DRY-RUN] kubectl create clusterrolebinding $SA_REVIEWER_BINDING ..."
    return 0
  fi

  # ServiceAccount
  if kubectl get serviceaccount "$SA_REVIEWER" -n "$NAMESPACE" &>/dev/null; then
    log_warn "ServiceAccount '$SA_REVIEWER' existe déjà, skip création."
  else
    kubectl create serviceaccount "$SA_REVIEWER" -n "$NAMESPACE"
    log_success "ServiceAccount '$SA_REVIEWER' créé"
  fi

  # ClusterRoleBinding
  if kubectl get clusterrolebinding "$SA_REVIEWER_BINDING" &>/dev/null; then
    log_warn "ClusterRoleBinding '$SA_REVIEWER_BINDING' existe déjà, skip."
  else
    kubectl create clusterrolebinding "$SA_REVIEWER_BINDING" \
      --clusterrole=system:auth-delegator \
      --serviceaccount="${NAMESPACE}:${SA_REVIEWER}"
    log_success "ClusterRoleBinding '$SA_REVIEWER_BINDING' créé (system:auth-delegator)"
  fi
}

# =============================================================================
# ÉTAPE 6 : GÉNÉRER LE JWT DU SA vault-auth
# =============================================================================
generate_jwt() {
  log_step "Étape 6 : Génération du JWT pour '$SA_REVIEWER'"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] kubectl create token $SA_REVIEWER -n $NAMESPACE --duration=$JWT_DURATION"
    JWT_VALUE="DRY_RUN_JWT_PLACEHOLDER"
    return 0
  fi

  JWT_VALUE=$(kubectl create token "$SA_REVIEWER" -n "$NAMESPACE" --duration="$JWT_DURATION")

  if [[ -z "$JWT_VALUE" ]]; then
    log_error "JWT vide, vérifier que le SA '$SA_REVIEWER' existe bien."
    exit 1
  fi

  log_success "JWT généré (durée: $JWT_DURATION)"
  log_info "JWT (10 premiers chars): ${JWT_VALUE:0:10}..."
}

# =============================================================================
# ÉTAPE 7 : CRÉER LE SERVICEACCOUNT app-sa
# =============================================================================
create_sa_app() {
  log_step "Étape 7 : ServiceAccount '$SA_APP' (namespace: $NAMESPACE)"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] kubectl create serviceaccount $SA_APP -n $NAMESPACE"
    return 0
  fi

  if kubectl get serviceaccount "$SA_APP" -n "$NAMESPACE" &>/dev/null; then
    log_warn "ServiceAccount '$SA_APP' existe déjà, skip création."
  else
    kubectl create serviceaccount "$SA_APP" -n "$NAMESPACE"
    log_success "ServiceAccount '$SA_APP' créé"
  fi
}

# =============================================================================
# ÉTAPE 8 : EXPORTER LE CERTIFICAT CA
# =============================================================================
export_ca_cert() {
  log_step "Étape 8 : Export du certificat CA → $CA_LOCAL_PATH"

  if [[ ! -f "$CA_CERT_PATH" ]]; then
    log_error "CA cert introuvable : $CA_CERT_PATH"
    exit 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] sudo cat $CA_CERT_PATH > $CA_LOCAL_PATH"
    CA_CONTENT="DRY_RUN_CA_PLACEHOLDER"
    return 0
  fi

  CA_CONTENT=$(sudo cat "$CA_CERT_PATH")
  echo "$CA_CONTENT" > "$CA_LOCAL_PATH"

  log_success "CA cert copié → $CA_LOCAL_PATH"
}

# =============================================================================
# ÉTAPE 9 : GÉNÉRER LE FICHIER JSON POUR LE SCRIPT VAULT
# =============================================================================
generate_vault_config_output() {
  log_step "Étape 9 : Génération du fichier de config pour enable-vault-k8s.sh"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] Fichier de sortie non généré."
    return 0
  fi

  cat > "$VAULT_OUTPUT" <<EOF
{
  "vault": {
    "addr": "http://VAULT_IP:30200",
    "unseal_key": "UNSEAL_KEY_ICI",
    "root_token": "ROOT_TOKEN_ICI"
  },
  "superadmin": {
    "username": "superadmin",
    "password": "MOT_DE_PASSE_ICI"
  },
  "kubernetes": {
    "host_ip": "${FLOATING_IP}",
    "ca_cert_path": "${CA_LOCAL_PATH}",
    "jwt": "${JWT_VALUE}",
    "namespace": "${NAMESPACE}",
    "sa_token_reviewer": "${SA_REVIEWER}",
    "sa_app": "${SA_APP}"
  },
  "vault_role": {
    "name": "app-role",
    "policy": "app-policy",
    "ttl": "1h"
  }
}
EOF

  log_success "Fichier généré : $VAULT_OUTPUT"
  log_warn "Remplir les champs VAULT_IP, UNSEAL_KEY_ICI, ROOT_TOKEN_ICI et MOT_DE_PASSE_ICI avant utilisation."
}

# =============================================================================
# RÉSUMÉ
# =============================================================================
print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}============================================================${NC}"
  echo -e "${GREEN}${BOLD} Cluster infra_app configuré avec succès${NC}"
  echo -e "${GREEN}${BOLD}============================================================${NC}"
  printf "  %-28s %s\n" "Floating IP (K8s host):"  "$FLOATING_IP"
  printf "  %-28s %s\n" "CA cert local:"            "$CA_LOCAL_PATH"
  printf "  %-28s %s\n" "SA token reviewer:"        "$SA_REVIEWER ($NAMESPACE)"
  printf "  %-28s %s\n" "SA app:"                   "$SA_APP ($NAMESPACE)"
  printf "  %-28s %s\n" "JWT duration:"             "$JWT_DURATION"
  echo ""
  echo -e "${BOLD}Prochaine étape :${NC}"
  echo -e "  1. Compléter $VAULT_OUTPUT (VAULT_IP, tokens)"
  echo -e "  2. Copier $CA_LOCAL_PATH sur la machine qui exécute enable-vault-k8s.sh"
  echo -e "  3. Lancer :"
  echo -e "     ./scripts/enable-vault-k8s.sh --config $VAULT_OUTPUT"
  echo ""
  if [[ "${DRY_RUN}" == false ]]; then
    echo -e "${BOLD}Vérifications rapides :${NC}"
    echo -e "  kubectl get sa -n $NAMESPACE"
    echo -e "  kubectl get clusterrolebinding $SA_REVIEWER_BINDING"
  fi
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  echo ""
  echo -e "${BOLD}${BLUE}============================================================${NC}"
  echo -e "${BOLD}${BLUE} Setup App Cluster — Vault K8s Auth Prep${NC}"
  echo -e "${BOLD}${BLUE}============================================================${NC}"
  [[ "$DRY_RUN"  == true ]] && log_warn "Mode DRY-RUN activé — aucune action réelle effectuée"
  [[ "$SKIP_K3S" == true ]] && log_warn "Mode --skip-k3s actif — k3s.service non modifié"
  echo ""

  validate_config
  load_config
  check_tls_san
  patch_k3s_service
  restart_k3s
  verify_tls_san
  create_sa_vault_auth
  generate_jwt
  create_sa_app
  export_ca_cert
  generate_vault_config_output
  print_summary
}

main "$@"
