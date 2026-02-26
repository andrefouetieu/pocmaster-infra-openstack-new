# Tools — Installation manuelle des charts Helm

Les outils (Vault, etc.) sont installés **manuellement** ou via `install_vault=true` (infra_platform) sur un cluster K8s créé par une infras (infra_platform, infra_app). Cette approche sépare l’infrastructure (Terraform) de la couche applicative (tools).

## Prérequis

- Un cluster K8s existant (créé via `terraform/infra_platform ou infra_app` avec `deploy_k8s = true`)
- `kubectl` configuré (kubeconfig pointant vers le cluster)
- `helm` installé

## Récupérer le kubeconfig

Si le cluster a été créé par une infras avec `k8s_master_floating_ip = true` :

```bash
cd terraform/infra_platform   # ou infra_app
MASTER_IP=$(terraform output -raw k8s_master_floating_ip)
ssh -i ~/.ssh/id_rsa $(terraform output -raw vm_ssh_user)@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$MASTER_IP/" > ~/.kube/config-platform
export KUBECONFIG=~/.kube/config-platform
```

## Outils disponibles

| Outil | Dossier | Installation |
|-------|---------|--------------|
| HashiCorp Vault | [vault/](vault/) | `./install.sh` |

## Ordre d’installation

Installer Vault en premier si d’autres services en dépendent.
