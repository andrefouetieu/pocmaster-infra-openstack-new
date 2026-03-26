# Argo CD sur Kubernetes (infra_platform)

Argo CD est déployé via **Helm (chart officiel argoproj)** sur le cluster K8s `infra_platform` et exposé en **NodePort 30080**. Il sert de moteur **GitOps** : il synchronise l'état du cluster avec les manifests versionnés dans Git.

---

## 0. Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Argo CD (namespace: argocd)                             │
│                                                          │
│  ┌─────────────────┐   ┌──────────────────────────────┐  │
│  │ argocd-server   │   │ argocd-application-controller│  │
│  │ (UI + API)      │   │ (reconcile loop)             │  │
│  │ NodePort 30080  │   └──────────────────────────────┘  │
│  └─────────────────┘                                     │
│  ┌─────────────────┐   ┌──────────────────────────────┐  │
│  │ argocd-repo-    │   │ argocd-applicationset-       │  │
│  │ server          │   │ controller                   │  │
│  │ (clone + render)│   │ (génération d'applications)  │  │
│  └─────────────────┘   └──────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
         ↕ sync
┌─────────────────────────────────────────────────────┐
│  Dépôt Git (gitops/)                                │
│  gitops/apps/<nom-app>/  ← manifests ou charts      │
│  gitops/argocd-apps/     ← Application CRD          │
└─────────────────────────────────────────────────────┘
```

| Composant | Rôle | Réplicas |
|-----------|------|----------|
| **argocd-server** | UI web + API | 1 |
| **application-controller** | Boucle de réconciliation (compare Git ↔ cluster) | 1 |
| **repo-server** | Clone les dépôts Git, rend les manifests | 1 |
| **applicationset-controller** | Génère des `Application` depuis des templates | 1 |
| **redis** | Cache interne | 1 |

---

## 1. Installation

### Prérequis

- Cluster K8s opérationnel (`infra_platform` avec `deploy_k8s = true`)
- `kubectl` et `helm` configurés
- Port 30080 ouvert dans le security group (automatique si `k8s_master_floating_ip = true`)

### Option A : Via Terraform (`install_argocd = true`)

Dans `terraform/infra_platform/terraform.tfvars` :

```hcl
install_argocd = true
```

Puis lancer :

```bash
cd terraform/infra_platform
terraform apply
```

Argo CD est installé automatiquement via Ansible après la création du cluster. Aucune action manuelle requise.

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

# Installer Argo CD
cd tools/argocd
./install.sh
```

### Option C : Via Ansible directement

Si le cluster est déjà créé et que tu veux relancer l'installation sans repasser par Terraform :

```bash
cd ansible
ansible-playbook -i envs/platform/00_inventory.yml argocd_install.yml
```

L'inventaire `envs/platform/00_inventory.yml` contient déjà l'IP du master, le user SSH et la clé. Si les IP ont changé, les mettre à jour :

```bash
cd terraform/infra_platform
terraform output k8s_master_floating_ip   # → mettre à jour ansible_host
terraform output vm_ssh_user              # → mettre à jour ansible_user
```

### Vérifier l'installation

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

Résultat attendu :

```
NAME                                               READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                   1/1     Running   0          2m
argocd-applicationset-controller-xxx              1/1     Running   0          2m
argocd-redis-xxx                                  1/1     Running   0          2m
argocd-repo-server-xxx                            1/1     Running   0          2m
argocd-server-xxx                                 1/1     Running   0          2m

NAME                    TYPE       CLUSTER-IP     PORT(S)          AGE
argocd-server           NodePort   10.43.x.x      80:30080/TCP     2m
argocd-redis            ClusterIP  10.43.x.x      6379/TCP         2m
argocd-repo-server      ClusterIP  10.43.x.x      8081/TCP         2m
```

---

## 2. Accès

### UI web via NodePort

```
http://<MASTER_IP>:30080
```

Récupérer l'IP du master :

```bash
cd terraform/infra_platform
terraform output -raw k8s_master_floating_ip
```

### Mot de passe admin initial

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Login : `admin` / mot de passe affiché ci-dessus.

**Changer le mot de passe après la première connexion** (UI → User Info → Update Password, ou CLI) :

```bash
argocd login <MASTER_IP>:30080 --username admin --password <MOT_DE_PASSE_INITIAL> --insecure
argocd account update-password
```

### CLI argocd (optionnel, en local)

```bash
# macOS
brew install argocd

# Se connecter
argocd login <MASTER_IP>:30080 --username admin --password <MOT_DE_PASSE> --insecure
```

### Port-forward (si NodePort non disponible)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# puis http://localhost:8080
```

---

## 3. Configuration (`values.yaml`)

| Paramètre | Description | Défaut |
|-----------|-------------|--------|
| `server.replicas` | Réplicas du serveur UI/API | `1` |
| `server.service.type` | Type de service | `NodePort` |
| `server.service.nodePortHttp` | Port NodePort pour l'UI | `30080` |
| `controller.replicas` | Réplicas du controller | `1` |
| `repoServer.replicas` | Réplicas du repo-server | `1` |
| `applicationSet.replicas` | Réplicas de l'applicationset-controller | `1` |
| `dex.enabled` | SSO (désactivé en démo) | `false` |
| `notifications.enabled` | Notifications (désactivé en démo) | `false` |
| `configs.params.server.insecure` | Désactiver TLS (reverse-proxy en amont) | `true` |
| `server.resources.requests.cpu` | CPU demandé | `200m` |
| `server.resources.requests.memory` | Mémoire demandée | `256Mi` |
| `controller.resources.requests.memory` | Mémoire controller | `512Mi` |
| `repoServer.resources.requests.memory` | Mémoire repo-server | `256Mi` |

---

## 4. Ajouter une application GitOps

### Structure Git recommandée

```
gitops/
  apps/
    demo-1/
      deployment.yaml
      service.yaml
  argocd-apps/
    demo-1.yaml     ← Application CRD pointant vers gitops/apps/demo-1/
```

### Manifest `Application` (gitops/argocd-apps/demo-1.yaml)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-1
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<ton-org>/<ton-repo>.git
    targetRevision: HEAD
    path: gitops/apps/demo-1
  destination:
    server: https://kubernetes.default.svc
    namespace: demo-1
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Appliquer le manifest

```bash
kubectl apply -f gitops/argocd-apps/demo-1.yaml
```

Argo CD va cloner le repo, lire `gitops/apps/demo-1/` et synchroniser l'état du cluster.

---

## 5. Flux GitOps

```
Tu commites → Git → Argo CD détecte le changement → synchronise le cluster
```

Avec `syncPolicy.automated`, la synchronisation est automatique dès qu'un commit est poussé sur la branche ciblée (`targetRevision`).

Sans `automated`, tu dois déclencher la sync manuellement :

```bash
argocd app sync demo-1
# ou via l'UI : bouton "Sync"
```

---

## 6. Monitoring

### Logs des pods

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f
```

### État des applications

```bash
argocd app list
argocd app get demo-1
```

### Ressources consommées

```bash
kubectl top pods -n argocd
```

---

## 7. Désinstallation

```bash
helm uninstall argocd -n argocd

# Supprimer le namespace
kubectl delete namespace argocd
```

---

## 8. Troubleshooting

### Pod argocd-server en CrashLoopBackOff

```bash
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --previous
```

Causes fréquentes :
- Ressources insuffisantes sur les workers (augmenter dans `values.yaml`)
- ConfigMap ou Secret manquant

### Impossible d'accéder à l'UI (port 30080)

- Vérifier que `k8s_master_floating_ip = true` (le security group ouvre le port 30080 automatiquement)
- Tester : `curl -I http://<MASTER_IP>:30080`
- Vérifier le service : `kubectl get svc -n argocd`

### Application en état `OutOfSync`

```bash
argocd app get <nom-app>
argocd app diff <nom-app>
```

Cause fréquente : un changement a été fait directement dans le cluster (hors Git). Avec `selfHeal: true`, Argo CD le corrige automatiquement.

### Application en état `Unknown` ou `Error`

```bash
argocd app get <nom-app>
kubectl describe application <nom-app> -n argocd
```

Vérifier que le repo Git est accessible depuis le cluster et que le `path` existe.

---

## Références

- [Chart Helm officiel Argo CD](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)
- [Documentation Argo CD](https://argo-cd.readthedocs.io/)
- [tools/argocd/](../tools/argocd/)
