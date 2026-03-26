#!/usr/bin/env bash
# Bootstrap Argo CD : secret repository (optionnel) + Application racine.
# Variables d'environnement :
#   SAGA_BOOTSTRAP_DIR  (obligatoire) répertoire contenant root-application.yaml et
#                         repository-secret.yaml.template si secret requis
#   ARGOCD_NAMESPACE    défaut : argocd
#   ARGOCD_BOOTSTRAP_APPLY_REPO_SECRET  true|false — si true, GIT_TOKEN requis
#   GIT_TOKEN             PAT Git (si apply secret)

set -euo pipefail

: "${SAGA_BOOTSTRAP_DIR:?définir SAGA_BOOTSTRAP_DIR}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
apply="${ARGOCD_BOOTSTRAP_APPLY_REPO_SECRET:-true}"

if [[ ! -f "${SAGA_BOOTSTRAP_DIR}/root-application.yaml" ]]; then
  echo "Fichier manquant : ${SAGA_BOOTSTRAP_DIR}/root-application.yaml" >&2
  exit 1
fi

if [[ "${apply}" == "true" ]]; then
  : "${GIT_TOKEN:?GIT_TOKEN requis lorsque ARGOCD_BOOTSTRAP_APPLY_REPO_SECRET=true}"
  if [[ ! -f "${SAGA_BOOTSTRAP_DIR}/repository-secret.yaml.template" ]]; then
    echo "Fichier manquant : ${SAGA_BOOTSTRAP_DIR}/repository-secret.yaml.template" >&2
    exit 1
  fi
  if ! command -v envsubst >/dev/null 2>&1; then
    echo "envsubst introuvable (paquet gettext). Installez-le sur le nœud cible." >&2
    exit 1
  fi
  export GIT_TOKEN
  envsubst < "${SAGA_BOOTSTRAP_DIR}/repository-secret.yaml.template" \
    | kubectl apply -n "${ARGOCD_NAMESPACE}" -f -
fi

kubectl apply -f "${SAGA_BOOTSTRAP_DIR}/root-application.yaml"
