#!/usr/bin/env bash
# Enregistre un cluster workloads dans Argo CD via un Secret Kubernetes.
# Variables d'environnement :
#   SAGA_BOOTSTRAP_DIR        (obligatoire) répertoire contenant cluster-secret-saga-workload-dev.yaml.template
#   ARGOCD_NAMESPACE          défaut : argocd
#   WORKLOAD_BEARER_TOKEN     (obligatoire) token du SA argocd-manager sur le cluster workloads
#   WORKLOAD_CA_DATA          (obligatoire) CA base64 du cluster workloads

set -euo pipefail

: "${SAGA_BOOTSTRAP_DIR:?définir SAGA_BOOTSTRAP_DIR}"
: "${WORKLOAD_BEARER_TOKEN:?définir WORKLOAD_BEARER_TOKEN}"
: "${WORKLOAD_CA_DATA:?définir WORKLOAD_CA_DATA}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

TEMPLATE="${SAGA_BOOTSTRAP_DIR}/cluster-secret-saga-workload-dev.yaml.template"

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Fichier manquant : ${TEMPLATE}" >&2
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst introuvable (paquet gettext). Installez-le sur le nœud cible." >&2
  exit 1
fi

export WORKLOAD_BEARER_TOKEN WORKLOAD_CA_DATA

envsubst < "${TEMPLATE}" | kubectl apply -n "${ARGOCD_NAMESPACE}" -f -

echo "Cluster secret appliqué. Vérifier avec : kubectl -n ${ARGOCD_NAMESPACE} get secrets -l argocd.argoproj.io/secret-type=cluster"
