# Accès SSH et communication dans le cluster K8s

---

## 0. Utilisateur SSH sur les VMs

Les VMs sont créées avec un **utilisateur Linux** configuré par cloud-init (ta clé SSH est ajoutée pour cet utilisateur). Ansible se connecte avec **`-u <cet utilisateur>`** (voir `06_ansible_k3s.tf`).

Tu choisis cet utilisateur via la variable **`vm_ssh_user`** dans `terraform.tfvars` (ex. `vm_ssh_user = "ubuntu"` ou ton login Unix). C’est le même user pour SSH et pour Ansible. Par défaut le template utilisait `xavki` ; tu peux mettre **ton propre login** (ex. `mac`, `ton_nom`, `ubuntu`).

Dans les exemples ci-dessous, remplace `xavki` par la valeur de **`vm_ssh_user`** si tu l’as modifiée.

---

## 1. Les 3 machines peuvent-elles communiquer pour K8s ?

**Oui, sans problème.** Voici pourquoi :

### Configuration réseau

- **Toutes les 3 machines** (1 master + 2 workers) sont sur le **même réseau** : `cluster_network` (subnet **10.0.2.0/24** par défaut).
- Elles reçoivent des IP dans ce subnet (ex. master = 10.0.2.10, worker1 = 10.0.2.11, worker2 = 10.0.2.12).

### Security groups

Chaque machine a le security group **`cluster-all-internal`** qui autorise :
- **TCP** : ports **1-65535** depuis le subnet 10.0.2.0/24
- **UDP** : ports **1-65535** depuis le subnet 10.0.2.0/24

Donc :
- ✅ Le master peut communiquer avec les workers (et vice versa).
- ✅ Les ports nécessaires pour K8s sont ouverts :
  - **6443** (API Kubernetes) : master ↔ workers
  - **10250** (kubelet) : master ↔ workers
  - **8472** (Flannel/VXLAN) : workers ↔ workers
  - Et tous les autres ports nécessaires pour K3s

**Conclusion** : la configuration actuelle permet un cluster K8s fonctionnel. Les 3 machines peuvent communiquer entre elles sans problème.

---

## 2. Commandes SSH pour se connecter au cluster

### Option A : Avec IP flottante sur le master (`k8s_master_floating_ip = true`)

**Récupérer l'IP flottante :**
```bash
cd terraform/02_cluster
terraform output k8s_master_floating_ip
```

**SSH au master :**
```bash
ssh -i ~/.ssh/id_rsa <vm_ssh_user>@<IP_FLOTTANTE_MASTER>
```

**Exemple (si vm_ssh_user = "ubuntu") :**
```bash
ssh -i ~/.ssh/id_rsa ubuntu@195.15.193.45
```

### Option B : Sans IP flottante (accès depuis le réseau privé)

**Récupérer l'IP interne du master :**
```bash
cd terraform/02_cluster
terraform output k8s_master_internal_ip
```

**SSH au master :**
```bash
ssh -i ~/.ssh/id_rsa <vm_ssh_user>@<IP_INTERNE_MASTER>
```

**Exemple (si vm_ssh_user = "ubuntu") :**
```bash
ssh -i ~/.ssh/id_rsa ubuntu@10.0.2.10
```

⚠️ **Important** : pour cette option, tu dois être sur une machine qui a accès au subnet 10.0.2.0/24 (ex. une autre VM dans le même réseau, ou via VPN avec routage vers ce subnet).

---

## 3. Dois-tu te connecter au master seulement ou aussi aux workers ?

### Pour utiliser le cluster (kubectl) : **master seulement**

Une fois connecté au master, tu récupères la kubeconfig :

```bash
ssh -i ~/.ssh/id_rsa <vm_ssh_user>@<MASTER_IP> "sudo cat /etc/rancher/k3s/k3s.yaml"
```

Puis tu l'enregistres sur ta machine locale (ex. `~/.kube/config`) et tu utilises `kubectl` depuis ton poste :

```bash
kubectl get nodes
kubectl get pods -A
kubectl apply -f mon-deployment.yaml
```

**Tu n'as pas besoin de te connecter aux workers** pour utiliser le cluster. `kubectl` communique avec l'API du master (port 6443), et le master orchestre les workers.

### Quand se connecter aux workers ?

Seulement pour :
- **Debug/maintenance** : vérifier les logs, les ressources système, etc.
- **Dépannage** : si un worker a un problème spécifique

**Exemple de connexion à un worker :**
```bash
# Récupérer les IPs des workers
terraform output k8s_worker_internal_ips

# SSH au worker1
ssh -i ~/.ssh/id_rsa <vm_ssh_user>@10.0.2.11

# Vérifier le statut k3s-agent
sudo systemctl status k3s-agent
```

---

## Résumé

| Question | Réponse |
|----------|---------|
| **Les 3 machines communiquent-elles ?** | ✅ Oui, via le security group `cluster-all-internal` (TCP/UDP 1-65535 sur le subnet). |
| **Quelle commande SSH pour le master ?** | `ssh -i ~/.ssh/id_rsa <vm_ssh_user>@<IP>` (flottante si configurée, sinon interne). |
| **Dois-je me connecter aux workers ?** | ❌ Non pour utiliser le cluster (kubectl). ✅ Seulement pour debug/maintenance. |

**En pratique** : connecte-toi au master, récupère la kubeconfig, utilise `kubectl` depuis ton poste. Les workers sont gérés automatiquement par le master.

---

## 4. Port-forwarding avec kubectl

**Oui, tu peux faire du port-forwarding**, mais il faut que **`k8s_master_floating_ip = true`** pour que ça fonctionne depuis ta machine locale.

### Pourquoi ?

`kubectl port-forward` a besoin d'accéder à l'**API Kubernetes** (port **6443**) sur le master. Si le master n'a pas d'IP flottante, tu ne peux pas joindre le port 6443 depuis internet.

### Configuration requise

1. **Activer l'IP flottante** dans `terraform.tfvars` :
   ```hcl
   k8s_master_floating_ip = true
   ```

2. **Récupérer la kubeconfig** et la configurer pour pointer vers l'IP flottante :
   ```bash
   # Récupérer la kubeconfig depuis le master
   ssh -i ~/.ssh/id_rsa <vm_ssh_user>@<MASTER_FLOATING_IP> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
   
   # Modifier le fichier pour utiliser l'IP flottante au lieu de l'IP interne
   # Dans ~/.kube/config, changer le champ server:
   # server: https://<MASTER_FLOATING_IP>:6443
   ```

3. **Vérifier la connexion** :
   ```bash
   kubectl get nodes
   ```

### Utiliser port-forward

Une fois la kubeconfig configurée, tu peux faire du port-forward depuis ta machine :

```bash
# Port-forward vers un service (ex. service "mon-app" sur le port 8080)
kubectl port-forward service/mon-app 8080:8080

# Port-forward vers un pod directement
kubectl port-forward pod/mon-pod-123 8080:8080

# Port-forward vers un deployment
kubectl port-forward deployment/mon-deployment 8080:8080
```

Puis tu accèdes à ton service via `http://localhost:8080` sur ta machine.

### Sans IP flottante

Si `k8s_master_floating_ip = false`, tu ne peux pas faire de port-forward depuis ta machine locale. Tu dois :
- Soit être sur une machine qui a accès au subnet 10.0.2.0/24
- Soit utiliser un VPN avec routage vers ce subnet
- Soit faire le port-forward depuis le master lui-même (SSH au master, puis `kubectl port-forward` depuis là)

---

## Résumé complet

| Question | Réponse |
|----------|---------|
| **Les 3 machines communiquent-elles ?** | ✅ Oui, via le security group `cluster-all-internal` (TCP/UDP 1-65535 sur le subnet). |
| **Quelle commande SSH pour le master ?** | `ssh -i ~/.ssh/id_rsa <vm_ssh_user>@<IP>` (flottante si configurée, sinon interne). |
| **Dois-je me connecter aux workers ?** | ❌ Non pour utiliser le cluster (kubectl). ✅ Seulement pour debug/maintenance. |
| **Puis-je faire du port-forwarding ?** | ✅ Oui, si `k8s_master_floating_ip = true` (port 6443 ouvert depuis internet). |
