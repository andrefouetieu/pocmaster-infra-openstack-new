# Argo CD — GitOps via Helm

## Prérequis

- Cluster K8s opérationnel (infra_platform ou infra_app avec `deploy_k8s = true`)
- `kubectl` et `helm` configurés

## Installation

```bash
cd tools/argocd
./install.sh
```

## Configuration

Le contenu de `tools/argocd/` est la **source unique** utilisée par :

- `./install.sh` (installation manuelle)
- Le rôle Ansible `argocd_helm` (quand `install_argocd=true` dans Terraform) — copie ce répertoire sur le master et exécute `install.sh`

Il définit :

- **server.service.type** : NodePort 30080 pour accès depuis internet
- **configs.params.server.insecure** : true (TLS désactivé pour simplifier en démo)
- **dex.enabled** : false (pas de SSO en démo)
- **1 réplica** par composant (server, controller, repo-server, applicationSet)
- **Ressources** modestes adaptées au cluster de démo K3s

Adapter `values.yaml` selon l'environnement (dev/prod).

## Accès

**UI web via NodePort :**

```
http://<MASTER_IP>:30080
```

Récupérer l'IP du master : `terraform output -raw k8s_master_floating_ip` (depuis `terraform/infra_platform` ou `infra_app`).

**Ou via port-forward (si besoin) :**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# puis http://localhost:8080
```

**Mot de passe admin initial :**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
```

Login : `admin` / mot de passe affiché.

## Documentation complète

Voir [docs/ARGOCD-SETUP.md](../../docs/ARGOCD-SETUP.md) pour la configuration GitOps et l'ajout d'applications.
