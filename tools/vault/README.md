# Vault — HashiCorp Vault via Helm

## Prérequis

- Cluster K8s opérationnel (infra_platform avec `deploy_k8s = true`)
- `kubectl` et `helm` configurés

## Installation

```bash
cd tools/vault
./install.sh
```

## Configuration

Le contenu de `tools/vault/` est la **source unique** utilisée par :

- `./install.sh` (installation manuelle)
- Le rôle Ansible `vault_helm` (quand `install_vault=true` dans Terraform) — copie ce répertoire sur le master et exécute `install.sh`

Il définit :

- **server.standalone.enabled** : mode standalone
- **server.service.type** : NodePort 30200 pour accès externe
- **ui.enabled** : interface web
- **injector.enabled** : désactivé par défaut

Adapter `values.yaml` selon l’environnement (dev/prod).

## Accès

- **API** : `http://<MASTER_IP>:30200` (ou IP de n’importe quel nœud)
- **UI** : `http://<MASTER_IP>:30200/ui`

Récupérer l’IP du master : `terraform output -raw k8s_master_floating_ip` (depuis `terraform/infra_platform`).

## Documentation complète

Pour l'authentification (user/password, SSO, Active Directory) : [docs/VAULT.md](../../docs/VAULT.md).
