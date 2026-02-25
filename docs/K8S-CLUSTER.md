# Cluster Kubernetes (K3s) — stack 02 indépendant

Le stack **02** (cluster K8s) est **autonome** : tu peux le lancer **sans avoir déployé 01_vpn**. Il crée son propre réseau, sa propre keypair et ses propres security groups.

Tu peux renommer le dossier `02_infrastructure` en **`02_clusters`** si tu préfères ; le contenu reste le même.

---

## Pourquoi 02 peut tourner sans 01

| Dépendance | Avant (02 dépendait de 01) | Maintenant (02 indépendant) |
|------------|----------------------------|-----------------------------|
| **Réseau** | Réseau `internal_dev` créé par 01_vpn | 02 crée son réseau `cluster_network` (subnet 10.0.2.0/24 par défaut) |
| **Keypair** | Keypair `default_key` créée par 01_vpn | 02 crée sa keypair `cluster_key` |
| **Security groups** | Groupes `all_internal`, `ssh-internal` dans 01_vpn | 02 crée `cluster-ssh-internal`, `cluster-all-internal` |

Donc : **tu n’as plus besoin de 01_vpn pour déployer le cluster.**

---

## Architecture

- **1 nœud master** : `k8s-master1`
- **2 nœuds workers** : `k8s-worker1`, `k8s-worker2`
- **Réseau** : `cluster_network`, subnet **10.0.2.0/24** (par défaut)
- **Accès** :
  - Sans VPN : option **IP flottante sur le master** (`k8s_master_floating_ip = true`) pour SSH et `kubectl` depuis internet.
  - Avec VPN (si 01_vpn est aussi déployé) : les deux subnets (10.0.1.0/24 et 10.0.2.0/24) sont distincts ; pour joindre le cluster via le VPN il faudrait un routage ou une machine dans les deux réseaux.

---

## 1. Déployer uniquement le cluster (sans 01_vpn)

```bash
cd terraform/02_infrastructure   # ou 02_clusters si tu as renommé
cp terraform.tfvars.example terraform.tfvars   # si tu as un exemple
# Renseigner au minimum ssh_public_key_default_user dans terraform.tfvars (ou TF_VAR_)
terraform init
terraform plan
terraform apply
```

Pour pouvoir te connecter au master **sans VPN**, mets dans tes variables :

```hcl
k8s_master_floating_ip = true
```

Tu récupères l’IP flottante du master avec :

```bash
terraform output k8s_master_floating_ip
```

Puis SSH et récupération de la kubeconfig :

```bash
ssh -i ~/.ssh/id_rsa xavki@$(terraform output -raw k8s_master_floating_ip) "sudo cat /etc/rancher/k3s/k3s.yaml"
```

(Si tu n’actives pas l’IP flottante, les nœuds ne sont accessibles que depuis une machine déjà dans le subnet 10.0.2.0/24, par ex. une autre VM OpenStack sur le même réseau.)

---

## 2. Installer K3s (Ansible)

Une fois les 3 VMs créées, remplis l’inventaire avec les IP (internes ou flottante du master) :

```bash
terraform output k8s_master_internal_ip
terraform output k8s_worker_internal_ips
```

Copie `ansible/envs/dev/01_inventory_k8s.yml.example` en `01_inventory_k8s.yml`, mets ces IP (et user `xavki`, clé SSH), puis :

```bash
cd ansible
ansible-playbook -i envs/dev/01_inventory_k8s.yml k8s_cluster.yml -u xavki --private-key ~/.ssh/id_rsa
```

---

## 3. Utiliser le cluster (kubectl)

- **Avec IP flottante sur le master** : dans la kubeconfig, `server` doit pointer vers `https://<k8s_master_floating_ip>:6443`.
- **Sans IP flottante** : tu dois être sur une machine qui a accès au subnet 10.0.2.0/24 (ex. jump host dans le même réseau), puis `server: https://<k8s_master_internal_ip>:6443`.

Ensuite : `kubectl get nodes`, `kubectl get pods -A`, et déploiement de tes projets K8s comme d’habitude.

### Configuration kubectl sur le master (optionnel)

Pour utiliser `kubectl` sans `sudo` lorsque tu te connectes en SSH sur le master, lance le playbook de configuration kubectl (même inventaire et options que `k8s_cluster.yml`) :

```bash
cd ansible
ansible-playbook -i envs/dev/01_inventory_k8s.yml k8s_kubectl_config.yml -u xavki --private-key ~/.ssh/id_rsa
```

Cela copie `/etc/rancher/k3s/k3s.yaml` vers `~/.kube/config` pour ton utilisateur SSH et ajoute `KUBECONFIG` dans `~/.bashrc`. Après coup, en SSH sur le master, `kubectl` fonctionne sans sudo.

### Installer Helm

Pour installer Helm sur le master et travailler avec les charts :

```bash
cd ansible
ansible-playbook -i envs/dev/01_inventory_k8s.yml k8s_helm.yml -u xavki --private-key ~/.ssh/id_rsa
```

Helm est installé dans `/usr/local/bin/helm` sur le master. Tu peux ensuite utiliser `helm` en SSH sur le master ou depuis ta machine si tu pointes `kubectl` / kubeconfig vers le cluster.

---

## Ordre si tu utilises les deux stacks

1. **02 (cluster)** peut être appliqué **seul**.
2. **01 (VPN)** peut être appliqué **seul**.
3. Les deux peuvent coexister (réseaux différents : 10.0.1.0/24 et 10.0.2.0/24).

Pour accéder au cluster **via le VPN** tout en gardant 02 indépendant, il faudrait soit une VM dans les deux réseaux, soit du routage entre 10.0.1.0/24 et 10.0.2.0/24 (hors scope de ce doc).
