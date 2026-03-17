#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
RELEASE_NAME="${ARGOCD_RELEASE:-argocd}"

if ! kubectl cluster-info &>/dev/null; then
  echo "Erreur: kubectl ne pointe pas vers un cluster valide. Configure KUBECONFIG."
  exit 1
fi

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE_NAME" argo/argo-cd \
  -n "$NAMESPACE" \
  -f values.yaml \
  --wait --timeout 10m

echo ""
echo "Argo CD installé dans le namespace '$NAMESPACE'."
echo ""
echo "Accès à l'UI via NodePort 30080 :"
echo "  http://<MASTER_IP>:30080"
echo ""
echo "Mot de passe admin initial :"
echo "  kubectl -n ${NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
