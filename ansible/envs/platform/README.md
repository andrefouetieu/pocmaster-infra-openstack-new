# Ansible — Environnement platform

Inventaire pour le cluster **infra_platform** (Vault, MongoDB, K3s).

## Utilisation

```bash
cd ansible

# Vault
ansible-playbook -i envs/platform/00_inventory.yml vault_install.yml

# MongoDB (renseigner rootPassword et replicaSetKey dans tools/mongodb/values.yaml avant)
ansible-playbook -i envs/platform/00_inventory.yml mongodb_install.yml

# Argo CD (installation Helm)
ansible-playbook -i envs/platform/00_inventory.yml argocd_install.yml

# Argo CD — bootstrap GitOps (secret repo + Application racine saga), une fois Argo CD installé
# Logique : ../scripts/argocd-bootstrap.sh (racine infra-openstack ; kubectl en root, become: true)
# Renseigner saga_gitops_repo_root (clone local du dépôt saga-orchestration-case-study) et le token si besoin
ansible-playbook -i envs/platform/00_inventory.yml argocd-bootstrap.yml \
  -e saga_gitops_repo_root=/chemin/absolu/vers/saga-orchestration-case-study \
  -e argocd_git_token=ghp_xxx
```

## Mettre à jour les IP

Depuis la racine du projet :

```bash
cd terraform/infra_platform
terraform output k8s_master_floating_ip
terraform output vm_ssh_user
```

Éditer `envs/platform/00_inventory.yml` et mettre à jour `ansible_host` et `ansible_user`.
