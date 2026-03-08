#!/bin/bash
# =============================================================================
# enable-vault-k8s.sh
# Configure Vault Kubernetes Auth Method à partir d'un fichier JSON
#
# Usage: ./enable-vault-k8s.sh --config /path/to/config.json
#
# Dépendances : vault (CLI), jq, curl
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
Usage: $(basename "$0") --config <fichier.json>

Options:
  --config   Chemin vers le fichier de configuration JSON (obligatoire)
  --dry-run  Affiche les actions sans les exécuter
  --help     Affiche cette aide

Exemple:
  $(basename "$0") --config scripts/config.json

Structure du fichier JSON attendue : voir scripts/config.example.json
EOF
  exit 0
}

# =============================================================================
# PARSING DES ARGUMENTS
# =============================================================================
CONFIG_FILE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true;     shift   ;;
    --help)    usage ;;
    *) log_error "Argument inconnu : $1"; usage ;;
  esac
done

# =============================================================================
# VALIDATION ET LECTURE DU JSON
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
    log_error "'jq' est requis pour lire le fichier JSON. Installer : apt install jq / brew install jq"
    exit 1
  fi

  if ! command -v vault &>/dev/null; then
    log_error "'vault' CLI non trouvé dans PATH."
    exit 1
  fi

  if ! command -v curl &>/dev/null; then
    log_error "'curl' non trouvé dans PATH."
    exit 1
  fi

  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log_error "Fichier JSON invalide : $CONFIG_FILE"
    exit 1
  fi

  log_success "Fichier de config valide : $CONFIG_FILE"
}

load_config() {
  VAULT_ADDR=$(jq -r '.vault.addr'        "$CONFIG_FILE")
  UNSEAL_KEY=$(jq -r '.vault.unseal_key'  "$CONFIG_FILE")
  ROOT_TOKEN=$(jq -r '.vault.root_token'  "$CONFIG_FILE")

  SUPERADMIN_USER=$(jq -r '.superadmin.username // "superadmin"' "$CONFIG_FILE")
  SUPERADMIN_PASS=$(jq -r '.superadmin.password // ""'           "$CONFIG_FILE")

  K8S_IP=$(jq -r '.kubernetes.host_ip'           "$CONFIG_FILE")
  CA_CERT=$(jq -r '.kubernetes.ca_cert_path'      "$CONFIG_FILE")
  JWT=$(jq -r '.kubernetes.jwt'                   "$CONFIG_FILE")
  NAMESPACE=$(jq -r '.kubernetes.namespace // "default"'         "$CONFIG_FILE")
  SA_TOKEN_REVIEWER=$(jq -r '.kubernetes.sa_token_reviewer // "vault-auth"' "$CONFIG_FILE")
  SA_APP=$(jq -r '.kubernetes.sa_app // "app-sa"'                "$CONFIG_FILE")

  ROLE_NAME=$(jq -r '.vault_role.name   // "app-role"'   "$CONFIG_FILE")
  POLICY_NAME=$(jq -r '.vault_role.policy // "app-policy"' "$CONFIG_FILE")
  TTL=$(jq -r '.vault_role.ttl          // "1h"'          "$CONFIG_FILE")

  # Validation des champs obligatoires
  local errors=0
  for var_name in VAULT_ADDR UNSEAL_KEY ROOT_TOKEN K8S_IP CA_CERT JWT; do
    local val="${!var_name}"
    if [[ -z "$val" || "$val" == "null" ]]; then
      log_error "Champ manquant dans le JSON : $var_name"
      errors=$((errors + 1))
    fi
  done

  if [[ ! -f "$CA_CERT" ]]; then
    log_error "ca_cert_path introuvable : $CA_CERT"
    errors=$((errors + 1))
  fi

  [[ $errors -gt 0 ]] && { log_error "$errors erreur(s) dans la config. Arrêt."; exit 1; }

  export VAULT_ADDR
  export VAULT_TOKEN="$ROOT_TOKEN"

  log_success "Configuration chargée"
  log_info "  Vault addr      : $VAULT_ADDR"
  log_info "  K8s host        : https://${K8S_IP}:6443"
  log_info "  CA cert         : $CA_CERT"
  log_info "  SA reviewer     : $SA_TOKEN_REVIEWER ($NAMESPACE)"
  log_info "  SA app          : $SA_APP ($NAMESPACE)"
  log_info "  Role / Policy   : $ROLE_NAME / $POLICY_NAME"
  log_info "  TTL             : $TTL"
  log_info "  Superadmin user : $SUPERADMIN_USER"
}

# =============================================================================
# ÉTAPE 1 : VÉRIFICATION ACCÈS VAULT
# =============================================================================
check_vault_reachable() {
  log_step "Étape 1 : Vérification de l'accès Vault"

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" || true)

  if [[ "$http_code" == "000" ]]; then
    log_error "Vault inaccessible à $VAULT_ADDR"
    exit 1
  fi

  log_success "Vault accessible (HTTP $http_code)"
}

# =============================================================================
# ÉTAPE 2 : UNSEAL VAULT
# =============================================================================
unseal_vault() {
  log_step "Étape 2 : Unseal Vault"

  local sealed
  sealed=$(vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")

  if [[ "$sealed" == "false" ]]; then
    log_warn "Vault est déjà unsealed, skip."
    return 0
  fi

  log_info "Vault est sealed. Unseal en cours..."

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault operator unseal <key>"
    return 0
  fi

  vault operator unseal "$UNSEAL_KEY"

  sealed=$(vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")
  if [[ "$sealed" == "true" ]]; then
    log_error "Vault est toujours sealed après unseal."
    log_warn "Vérifier que le threshold est bien 1 dans votre init Vault."
    exit 1
  fi

  log_success "Vault unsealed avec succès"
}

# =============================================================================
# ÉTAPE 3 : LOGIN VAULT
# =============================================================================
vault_login() {
  log_step "Étape 3 : Vérification du token root"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault token lookup"
    return 0
  fi

  if ! vault token lookup &>/dev/null; then
    log_error "Root token invalide ou expiré."
    exit 1
  fi

  log_success "Token root valide"
}

# =============================================================================
# ÉTAPE 4 : CRÉATION DU SUPERADMIN
# =============================================================================
create_superadmin() {
  log_step "Étape 4 : Création du superadmin"

  if [[ -z "$SUPERADMIN_PASS" || "$SUPERADMIN_PASS" == "null" ]]; then
    log_warn "superadmin.password vide dans le JSON, skip création superadmin."
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault auth enable userpass"
    log_warn "[DRY-RUN] vault policy write superadmin ..."
    log_warn "[DRY-RUN] vault write auth/userpass/users/$SUPERADMIN_USER ..."
    return 0
  fi

  # Activer userpass si pas encore activé
  if vault auth list -format=json 2>/dev/null | jq -e '."userpass/"' &>/dev/null; then
    log_warn "Auth userpass déjà activée, skip."
  else
    vault auth enable userpass
    log_success "Auth userpass activée"
  fi

  # Policy superadmin (accès total, équivalent root)
  vault policy write superadmin - <<'EOF'
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
  log_success "Policy 'superadmin' créée"

  # Création du user
  vault write "auth/userpass/users/${SUPERADMIN_USER}" \
    password="$SUPERADMIN_PASS" \
    policies="superadmin"

  log_success "User '$SUPERADMIN_USER' créé avec policy superadmin (équivalent root)"
}

# =============================================================================
# ÉTAPE 5 : ACTIVER KUBERNETES AUTH
# =============================================================================
enable_k8s_auth() {
  log_step "Étape 5 : Activation de l'auth Kubernetes"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault auth enable kubernetes"
    return 0
  fi

  if vault auth list -format=json 2>/dev/null | jq -e '."kubernetes/"' &>/dev/null; then
    log_warn "Auth Kubernetes déjà activée, skip."
  else
    vault auth enable kubernetes
    log_success "Auth Kubernetes activée"
  fi
}

# =============================================================================
# ÉTAPE 6 : CONFIGURER KUBERNETES AUTH
# =============================================================================
configure_k8s_auth() {
  log_step "Étape 6 : Configuration de auth/kubernetes/config"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault write auth/kubernetes/config kubernetes_host=https://${K8S_IP}:6443 ..."
    return 0
  fi

  vault write auth/kubernetes/config \
    kubernetes_host="https://${K8S_IP}:6443" \
    kubernetes_ca_cert=@"$CA_CERT" \
    token_reviewer_jwt="$JWT"

  log_success "auth/kubernetes/config écrit"

  log_info "Configuration actuelle :"
  vault read auth/kubernetes/config
}

# =============================================================================
# ÉTAPE 7 : CRÉER LA POLICY APPLICATIVE
# =============================================================================
create_app_policy() {
  log_step "Étape 7 : Création de la policy '$POLICY_NAME'"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault policy write $POLICY_NAME ..."
    return 0
  fi

  vault policy write "$POLICY_NAME" - <<EOF
path "secret/data/app/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/app/*" {
  capabilities = ["list"]
}
EOF

  log_success "Policy '$POLICY_NAME' créée"
}

# =============================================================================
# ÉTAPE 8 : CRÉER LE RÔLE KUBERNETES
# =============================================================================
create_k8s_role() {
  log_step "Étape 8 : Création du rôle '$ROLE_NAME'"

  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN] vault write auth/kubernetes/role/$ROLE_NAME ..."
    return 0
  fi

  vault write "auth/kubernetes/role/${ROLE_NAME}" \
    bound_service_account_names="$SA_APP" \
    bound_service_account_namespaces="$NAMESPACE" \
    policies="$POLICY_NAME" \
    ttl="$TTL"

  log_success "Rôle '$ROLE_NAME' créé"
}

# =============================================================================
# RÉSUMÉ
# =============================================================================
print_summary() {
  echo ""
  echo -e "${GREEN}${BOLD}============================================================${NC}"
  echo -e "${GREEN}${BOLD} Configuration Vault K8s terminée avec succès${NC}"
  echo -e "${GREEN}${BOLD}============================================================${NC}"
  printf "  %-22s %s\n" "Vault addr:"       "$VAULT_ADDR"
  printf "  %-22s %s\n" "K8s host:"         "https://${K8S_IP}:6443"
  printf "  %-22s %s\n" "SA reviewer:"      "$SA_TOKEN_REVIEWER (ns: $NAMESPACE)"
  printf "  %-22s %s\n" "SA app:"           "$SA_APP (ns: $NAMESPACE)"
  printf "  %-22s %s\n" "Rôle Vault:"       "$ROLE_NAME"
  printf "  %-22s %s\n" "Policy Vault:"     "$POLICY_NAME"
  printf "  %-22s %s\n" "TTL token:"        "$TTL"
  if [[ -n "$SUPERADMIN_PASS" && "$SUPERADMIN_PASS" != "null" ]]; then
    printf "  %-22s %s\n" "Superadmin user:"  "$SUPERADMIN_USER"
  fi
  echo ""
  echo -e "${BOLD}Test depuis infra_app :${NC}"
  echo -e "  kubectl run -it --rm --image=curlimages/curl --restart=Never vault-test \\"
  echo -e "    --overrides='{\"spec\":{\"serviceAccountName\":\"${SA_APP}\"}}' -- sh -c \\"
  echo -e "    'JWT=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && \\"
  echo -e "     curl -s -X POST \\"
  echo -e "       --data \"{\\\"jwt\\\":\\\"\$JWT\\\",\\\"role\\\":\\\"${ROLE_NAME}\\\"}\" \\"
  echo -e "       ${VAULT_ADDR}/v1/auth/kubernetes/login'"
  echo ""
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  echo ""
  echo -e "${BOLD}${BLUE}============================================================${NC}"
  echo -e "${BOLD}${BLUE} Vault Kubernetes Auth Setup${NC}"
  echo -e "${BOLD}${BLUE}============================================================${NC}"
  [[ "$DRY_RUN" == true ]] && log_warn "Mode DRY-RUN activé — aucune action réelle effectuée"
  echo ""

  validate_config
  load_config
  check_vault_reachable
  unseal_vault
  vault_login
  create_superadmin
  enable_k8s_auth
  configure_k8s_auth
  create_app_policy
  create_k8s_role
  print_summary
}

main "$@"
