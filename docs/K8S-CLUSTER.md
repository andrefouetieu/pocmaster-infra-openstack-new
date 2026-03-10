# Cluster Kubernetes (K3s) — my_infra

Le cluster K8s est déployé via **my_infra** avec `deploy_k8s = true`. Il crée son propre réseau, keypair et security groups (préfixés par `infra_name` pour éviter les conflits multi-infra).

---

## Architecture

- **1 nœud master** : `{infra_name}-k8s-master1`
- **N nœuds workers** : `{infra_name}-k8s-worker1`, ... (configurable via `k8s_worker_count`)
- **Réseau** : `{infra_name}-cluster`, subnet **10.0.2.0/24** par défaut
- **Accès** : `k8s_master_floating_ip = true` pour SSH et `kubectl` depuis internet

---

## 1. Déployer le cluster

```bash
cd terraform/infra_platform
cp terraform.tfvars.example terraform.tfvars
# Renseigner : deploy_k8s = true, ssh_public_key_default_user, k8s_worker_count si besoin

terraform init
terraform plan
terraform apply
```

Pour accès depuis internet, `k8s_master_floating_ip = true` (défaut).

---

## 2. Récupérer le kubeconfig

```bash
cd terraform/infra_platform
MASTER_IP=$(terraform output -raw k8s_master_floating_ip)
ssh -i ~/.ssh/id_rsa $(terraform output -raw vm_ssh_user)@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/$MASTER_IP/" > ~/.kube/config-vault
export KUBECONFIG=~/.kube/config-vault
```

---

## 3. Utiliser le cluster

- **kubectl** : `kubectl get nodes`, `kubectl get pods -A`
- **Helm** : installer depuis `tools/` (ex. `tools/vault/install.sh`)

### Configuration kubectl sur le master

Le rôle `kubectl_config` est exécuté automatiquement par `k8s_cluster.yml` lors du déploiement. Il configure :

- **Utilisateur SSH** : `~/.kube/config` + `KUBECONFIG` dans `.bashrc`
- **root** : `/root/.kube/config` (pour `sudo kubectl`)
- **Persistance** : `/etc/profile.d/k8s-kubeconfig.sh` (chargé au login pour tous les utilisateurs)

### Installer Helm

```bash
ansible-playbook -i <inventaire> k8s_helm.yml -u <vm_ssh_user> --private-key ~/.ssh/id_rsa
```

---

## 4. Installer les outils (Vault, etc.)

Les outils sont installés **manuellement** depuis la section `tools/` :

```bash
cd tools/vault
./install.sh
```

Voir [tools/README.md](../tools/README.md) pour le détail.
