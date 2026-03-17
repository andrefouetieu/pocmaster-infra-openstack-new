#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="mongodb"

if ! kubectl cluster-info &>/dev/null; then
  echo "Erreur: kubectl ne pointe pas vers un cluster valide. Configure KUBECONFIG."
  exit 1
fi

echo "==> Déploiement MongoDB standalone (image officielle mongo:8.0)"
echo ""

# Vérifier que le secret a été personnalisé
ROOT_PWD=$(grep -oP 'MONGO_INITDB_ROOT_PASSWORD:\s*"\K[^"]+' manifests/secret.yaml 2>/dev/null || true)
if [[ -z "$ROOT_PWD" ]]; then
  echo "Erreur: MONGO_INITDB_ROOT_PASSWORD est vide dans manifests/secret.yaml."
  echo "Remplir les mots de passe avant installation."
  exit 1
fi

echo "==> Application des manifests..."
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/secret.yaml
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/statefulset.yaml

echo ""
echo "==> Attente que le pod soit Ready (max 5 min)..."
kubectl rollout status statefulset/mongodb -n "$NAMESPACE" --timeout=5m

echo ""
echo "MongoDB (standalone) installé dans le namespace '$NAMESPACE'."
echo ""
echo "Pod :"
kubectl get pods -n "$NAMESPACE" -l app=mongodb
echo ""
echo "PVC :"
kubectl get pvc -n "$NAMESPACE"
echo ""
echo "Service NodePort 30017 :"
kubectl get svc -n "$NAMESPACE"
echo ""
echo "Connexion :"
echo "  mongosh --host <NODE_IP> --port 30017 -u admin -p <MOT_DE_PASSE> --authenticationDatabase admin"
echo "  mongosh --host <NODE_IP> --port 30017 -u myappuser -p <MOT_DE_PASSE> --authenticationDatabase myappdb"
