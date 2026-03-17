#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="${MONGO_NAMESPACE:-mongodb}"
RELEASE_NAME="${MONGO_RELEASE:-mongodb}"

if ! kubectl cluster-info &>/dev/null; then
  echo "Erreur: kubectl ne pointe pas vers un cluster valide. Configure KUBECONFIG."
  exit 1
fi

# Vérifier que auth.rootPassword est renseigné ou qu'un secret existe
ROOT_PWD=$(grep -oP 'rootPassword:\s*"\K[^"]+' values.yaml 2>/dev/null || true)
EXISTING_SECRET=$(grep -oP 'existingSecret:\s*\K\S+' values.yaml 2>/dev/null || true)

if [[ -z "$ROOT_PWD" && -z "$EXISTING_SECRET" ]]; then
  echo "Erreur: auth.rootPassword est vide dans values.yaml et aucun existingSecret n'est défini."
  echo "Remplir auth.rootPassword ou créer un Secret K8s et renseigner auth.existingSecret."
  exit 1
fi

# Vérifier replicaSetKey si architecture=replicaset
ARCH=$(grep -oP '^\s*architecture:\s*\K\S+' values.yaml 2>/dev/null || true)
RS_KEY=$(grep -oP 'replicaSetKey:\s*"\K[^"]+' values.yaml 2>/dev/null || true)

if [[ "$ARCH" == "replicaset" && -z "$RS_KEY" && -z "$EXISTING_SECRET" ]]; then
  echo "Erreur: auth.replicaSetKey est vide dans values.yaml (requis en mode replicaset)."
  echo "Remplir auth.replicaSetKey avec une chaîne quelconque (ex: clé aléatoire)."
  exit 1
fi

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "$RELEASE_NAME" bitnami/mongodb \
  -n "$NAMESPACE" \
  -f values.yaml \
  --wait --timeout 10m

echo ""
echo "MongoDB installé dans le namespace '$NAMESPACE'."

if [[ "$ARCH" == "replicaset" ]]; then
  echo "Architecture : replica set (vérifier avec rs.status())"
  echo ""
  echo "Pods :"
  kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=mongodb 2>/dev/null || true
  echo ""
  echo "PVC :"
  kubectl get pvc -n "$NAMESPACE" 2>/dev/null || true
fi

echo ""
echo "Accès via NodePort 30017 sur n'importe quel nœud du cluster."
echo ""
echo "Connexion rapide :"
echo "  mongosh --host <NODE_IP> --port 30017 -u admin -p <MOT_DE_PASSE>"
