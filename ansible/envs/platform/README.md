# Ansible — Environnement platform

Inventaire pour le cluster **infra_platform** (Vault, MongoDB, K3s).

## Utilisation

```bash
cd ansible

# Vault
ansible-playbook -i envs/platform/00_inventory.yml vault_install.yml

# MongoDB (renseigner rootPassword et replicaSetKey dans tools/mongodb/values.yaml avant)
ansible-playbook -i envs/platform/00_inventory.yml mongodb_install.yml
```

## Mettre à jour les IP

Depuis la racine du projet :

```bash
cd terraform/infra_platform
terraform output k8s_master_floating_ip
terraform output vm_ssh_user
```

Éditer `envs/platform/00_inventory.yml` et mettre à jour `ansible_host` et `ansible_user`.
