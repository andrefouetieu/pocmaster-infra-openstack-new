#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Vérifier que kubectl est configuré
if ! kubectl cluster-info &>/dev/null; then
  echo "Erreur: kubectl ne pointe pas vers un cluster valide. Configure KUBECONFIG."
  exit 1
fi

# Ajouter le repo Helm HashiCorp
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update

# Créer le namespace si besoin
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

# Installer ou mettre à jour Vault
helm upgrade --install vault hashicorp/vault -n vault -f values.yaml --wait --timeout 5m

echo "Vault installé. Accès UI/API via NodePort 30200 sur un nœud du cluster."
