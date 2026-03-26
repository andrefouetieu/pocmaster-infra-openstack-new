# MongoDB sur Kubernetes (infra_platform)

MongoDB est déployé via **Helm (chart Bitnami)** sur le cluster K8s `infra_platform` en mode **replica set** (2 nœuds données + 1 arbiter) et exposé en **NodePort 30017**.

---

## 0. Architecture

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ mongodb-0       │  │ mongodb-1       │  │ mongodb-arbiter-0│
│ Primary         │  │ Secondary       │  │ (vote seul)     │
│ 5Gi PVC         │  │ 5Gi PVC         │  │ pas de données  │
│ lecture/écriture │  │ réplication     │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
       3 membres → quorum = 2 → failover automatique
```

| Rôle | Description | Stockage |
|------|-------------|----------|
| **Primary** | Reçoit les écritures et les lectures (par défaut) | 5Gi |
| **Secondary** | Copie des données du primary, peut servir les lectures | 5Gi |
| **Arbiter** | Participe au vote uniquement, pas de données | — |

**Total stockage** : ~10Gi (2 × 5Gi pour les nœuds données).

---

## 1. Installation

### Prérequis

- Cluster K8s opérationnel (`deploy_k8s = true`)
- `kubectl` et `helm` configurés
- `auth.rootPassword` et `auth.replicaSetKey` renseignés dans `tools/mongodb/values.yaml`

### Option A : Via Terraform (`install_mongodb=true`)

Dans `terraform/infra_platform/terraform.tfvars` :

```hcl
install_mongodb = true
```

Renseigner `auth.rootPassword` et `auth.replicaSetKey` dans `tools/mongodb/values.yaml` **avant** le `terraform apply`. MongoDB sera installé automatiquement via Ansible après la création du cluster.

### Option B : Installation manuelle (script)

```bash
# Récupérer l'IP du master
cd terraform/infra_platform
export MASTER_IP=$(terraform output -raw k8s_master_floating_ip)
export SSH_USER=$(terraform output -raw vm_ssh_user)

# Récupérer le kubeconfig
ssh -i ~/.ssh/id_rsa $SSH_USER@$MASTER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/$MASTER_IP/" > ~/.kube/config-platform
export KUBECONFIG=~/.kube/config-platform

# Installer MongoDB
cd tools/mongodb
nano values.yaml   # renseigner auth.rootPassword et auth.replicaSetKey
./install.sh
```

### Option C : Via Ansible directement

Si le cluster est déjà créé et que tu veux relancer l'installation sans repasser par Terraform :

```bash
cd ansible
ansible-playbook -i envs/platform/00_inventory.yml mongodb_install.yml
```

L'inventaire `envs/platform/00_inventory.yml` contient déjà l'IP du master, le user SSH et la clé. Si les IP ont changé, les mettre à jour :

```bash
cd terraform/infra_platform
terraform output k8s_master_floating_ip   # → mettre à jour ansible_host
terraform output vm_ssh_user              # → mettre à jour ansible_user
```

### Vérifier l'installation

```bash
kubectl get pods -n mongodb
kubectl get svc -n mongodb
kubectl get pvc -n mongodb
```

Résultat attendu :

```
NAME                      READY   STATUS    RESTARTS   AGE
mongodb-0                 1/1     Running   0          3m
mongodb-1                 1/1     Running   0          2m
mongodb-arbiter-0         1/1     Running   0          3m

NAME               TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)           AGE
mongodb            NodePort   10.43.x.x      <none>        27017:30017/TCP   3m
mongodb-headless   ClusterIP  None           <none>        27017/TCP         3m

NAME                          STATUS   VOLUME    CAPACITY   AGE
datadir-mongodb-0             Bound    pvc-xxx   5Gi        3m
datadir-mongodb-1             Bound    pvc-yyy   5Gi        2m
```

### Vérifier le replica set

```bash
kubectl exec -it mongodb-0 -n mongodb -- mongosh -u admin -p <MOT_DE_PASSE> --eval "rs.status()"
```

Les 3 membres doivent apparaître : 1 PRIMARY, 1 SECONDARY, 1 ARBITER.

---

## 2. Accès

### Depuis l'intérieur du cluster

URI replica set (recommandé) :

```
mongodb://admin:<MOT_DE_PASSE>@mongodb-0.mongodb-headless.mongodb.svc.cluster.local:27017,mongodb-1.mongodb-headless.mongodb.svc.cluster.local:27017/admin?replicaSet=rs0
```

URI via le service (le chart route vers le primary) :

```
mongodb://admin:<MOT_DE_PASSE>@mongodb.mongodb.svc.cluster.local:27017/admin
```

### Depuis l'extérieur (NodePort)

```bash
MASTER_IP=$(cd terraform/infra_platform && terraform output -raw k8s_master_floating_ip)
mongosh --host $MASTER_IP --port 30017 -u admin -p <MOT_DE_PASSE>
```

### Port-forward

```bash
kubectl port-forward -n mongodb svc/mongodb 27017:27017
mongosh "mongodb://admin:<MOT_DE_PASSE>@localhost:27017/admin"
```

### Depuis un pod dans le cluster

```bash
kubectl run -it --rm mongosh-test --image=mongo:7 --restart=Never -n mongodb -- \
  mongosh "mongodb://admin:<MOT_DE_PASSE>@mongodb-0.mongodb-headless.mongodb.svc.cluster.local:27017,mongodb-1.mongodb-headless.mongodb.svc.cluster.local:27017/admin?replicaSet=rs0"
```

---

## 3. Configuration (`values.yaml`)

| Paramètre | Description | Défaut |
|-----------|-------------|--------|
| `architecture` | `replicaset` ou `standalone` | `replicaset` |
| `replicaCount` | Nombre de nœuds avec données | `2` |
| `arbiter.enabled` | Activer l'arbiter (quorum) | `true` |
| `auth.rootUser` | Nom de l'admin | `admin` |
| `auth.rootPassword` | Mot de passe admin (obligatoire) | vide |
| `auth.replicaSetKey` | Clé partagée entre membres (obligatoire en replicaset) | vide |
| `auth.existingSecret` | Secret K8s au lieu des valeurs en clair | — |
| `persistence.enabled` | Activer le stockage persistant | `true` |
| `persistence.size` | Taille du volume par nœud | `5Gi` |
| `service.type` | Type de service K8s | `NodePort` |
| `service.nodePorts.mongodb` | Port externe | `30017` |
| `resources.requests.cpu` | CPU demandé par nœud | `250m` |
| `resources.requests.memory` | Mémoire demandée par nœud | `256Mi` |
| `resources.limits.cpu` | CPU max par nœud | `500m` |
| `resources.limits.memory` | Mémoire max par nœud | `512Mi` |
| `arbiter.resources.requests.cpu` | CPU demandé par l'arbiter | `100m` |
| `arbiter.resources.requests.memory` | Mémoire demandée par l'arbiter | `128Mi` |

---

## 4. Comportement du replica set

### Écritures et lectures

| Opération | Comportement |
|-----------|-------------|
| **Écritures** | Toujours sur le primary |
| **Lectures** | Par défaut sur le primary (configurable via read preference) |
| **Failover** | Si le primary tombe, le secondary est élu primary (quorum avec l'arbiter) |

### Failover automatique

Avec 3 membres (2 données + 1 arbiter), le quorum est de 2. Si le primary tombe :

1. L'arbiter et le secondary votent (2 votes = majorité)
2. Le secondary est promu primary
3. Les applications basculent automatiquement (si URI replica set)

Quand l'ancien primary revient, il rejoint comme secondary.

---

## 5. Gestion des utilisateurs

### Créer un utilisateur pour une application

Se connecter au primary :

```javascript
use myappdb
db.createUser({
  user: "myapp",
  pwd: "motdepasse",
  roles: [{ role: "readWrite", db: "myappdb" }]
})
```

### URI de connexion applicative (replica set)

```
mongodb://myapp:motdepasse@mongodb-0.mongodb-headless.mongodb.svc.cluster.local:27017,mongodb-1.mongodb-headless.mongodb.svc.cluster.local:27017/myappdb?replicaSet=rs0
```

### Lister les utilisateurs

```javascript
use admin
db.getUsers()
```

---

## 6. Stockage et persistance

Chaque nœud données utilise un **PersistentVolumeClaim** (PVC) indépendant. L'arbiter n'a pas de PVC.

### Vérifier les PVC

```bash
kubectl get pvc -n mongodb
# datadir-mongodb-0   Bound   5Gi
# datadir-mongodb-1   Bound   5Gi
```

### Capacité totale

| Composant | PVC | Taille |
|-----------|-----|--------|
| mongodb-0 (primary) | datadir-mongodb-0 | 5Gi |
| mongodb-1 (secondary) | datadir-mongodb-1 | 5Gi |
| mongodb-arbiter-0 | — | — |
| **Total** | | **10Gi** |

### Augmenter la taille du volume

Modifier `persistence.size` dans `values.yaml` puis relancer `./install.sh`. La StorageClass doit supporter l'expansion.

---

## 7. Sauvegardes

### Backup via mongodump

```bash
# Via port-forward
kubectl port-forward -n mongodb svc/mongodb 27017:27017 &
mongodump --host localhost --port 27017 \
  -u admin -p <MOT_DE_PASSE> --authenticationDatabase admin \
  --out ./backup-$(date +%Y%m%d)

# Via NodePort
mongodump --host <MASTER_IP> --port 30017 \
  -u admin -p <MOT_DE_PASSE> --authenticationDatabase admin \
  --out ./backup-$(date +%Y%m%d)
```

### Restaurer depuis un dump

```bash
mongorestore --host <HOST> --port <PORT> \
  -u admin -p <MOT_DE_PASSE> --authenticationDatabase admin \
  ./backup-20260220
```

---

## 8. Monitoring

### Logs des pods

```bash
kubectl logs -n mongodb mongodb-0 -f          # primary
kubectl logs -n mongodb mongodb-1 -f          # secondary
kubectl logs -n mongodb mongodb-arbiter-0 -f  # arbiter
```

### État du replica set

```bash
kubectl exec -it mongodb-0 -n mongodb -- mongosh -u admin -p <MOT_DE_PASSE> --eval "rs.status()"
```

### Métriques MongoDB

```javascript
db.serverStatus()
db.stats()
```

---

## 9. Connexion depuis infra_app

Pour que les applications sur **infra_app** accèdent à MongoDB sur **infra_platform**, utiliser l'IP flottante et le NodePort :

```
mongodb://myapp:motdepasse@<PLATFORM_FLOATING_IP>:30017/myappdb
```

Le port 30017 est ouvert automatiquement dès que `k8s_master_floating_ip = true` dans le security group (sans condition sur `install_mongodb`).

---

## 10. Désinstallation

```bash
helm uninstall mongodb -n mongodb

# Supprimer les PVC (attention : données perdues)
kubectl delete pvc -n mongodb --all

# Supprimer le namespace
kubectl delete namespace mongodb
```

---

## 11. Troubleshooting

### Pod en CrashLoopBackOff

```bash
kubectl describe pod mongodb-0 -n mongodb
kubectl logs -n mongodb mongodb-0 --previous
```

Causes fréquentes :
- `auth.rootPassword` ou `auth.replicaSetKey` non renseigné
- Ressources insuffisantes (augmenter dans `values.yaml`)
- PVC non provisionné (vérifier la StorageClass)

### Replica set sans primary

```bash
kubectl exec -it mongodb-0 -n mongodb -- mongosh -u admin -p <PWD> --eval "rs.status()"
```

Vérifier que les 3 membres apparaissent et que l'un est PRIMARY.

### Arbiter en Pending

L'arbiter n'a pas besoin de PVC. Si le pod est en Pending, vérifier les ressources (CPU/RAM) du cluster.

### Impossible de se connecter en externe

- Vérifier que `k8s_master_floating_ip = true` (le port 30017 est ouvert dans le security group dès qu'il y a une IP flottante)
- Tester la connectivité : `nc -zv <MASTER_IP> 30017`
- Vérifier le service : `kubectl get svc -n mongodb`

### Données perdues après redémarrage

- Vérifier que `persistence.enabled: true` dans `values.yaml`
- Vérifier les PVC : `kubectl get pvc -n mongodb`

### Un nœud ne rejoint pas le replica set

```bash
# Vérifier les logs du nœud
kubectl logs -n mongodb mongodb-1

# Forcer la reconfiguration (depuis le primary)
kubectl exec -it mongodb-0 -n mongodb -- mongosh -u admin -p <PWD> --eval "rs.conf()"
```

---

## Références

- [Chart Bitnami MongoDB](https://github.com/bitnami/charts/tree/main/bitnami/mongodb)
- [Documentation MongoDB Replica Set](https://www.mongodb.com/docs/manual/replication/)
- [Cheatsheet MongoDB](MONGODB-CHEATSHEET.md)
