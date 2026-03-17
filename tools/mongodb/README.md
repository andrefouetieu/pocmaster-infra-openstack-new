# MongoDB — Bitnami MongoDB via Helm

## Architecture

Replica set avec **2 nœuds données** + **1 arbiter** (vote seul, pas de données).

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ mongodb-0   │  │ mongodb-1   │  │ arbiter-0   │
│ Primary     │  │ Secondary   │  │ (vote seul) │
│ 5Gi PVC     │  │ 5Gi PVC     │  │ pas de PVC  │
└─────────────┘  └─────────────┘  └─────────────┘
     3 membres → quorum = 2 → failover automatique
```

## Prérequis

- Cluster K8s opérationnel (infra_platform avec `deploy_k8s = true`)
- `kubectl` et `helm` configurés
- `auth.rootPassword` et `auth.replicaSetKey` renseignés dans `values.yaml`

## Installation

```bash
cd tools/mongodb
# Éditer values.yaml : renseigner auth.rootPassword et auth.replicaSetKey
./install.sh
```

## Configuration

Le contenu de `tools/mongodb/` est la **source unique** utilisée par :

- `./install.sh` (installation manuelle)
- Le rôle Ansible `mongodb_helm` (quand `install_mongodb=true` dans Terraform infra_platform) — copie ce répertoire sur le master et exécute `install.sh`

`values.yaml` définit :

- **architecture** : `replicaset` (2 nœuds + 1 arbiter)
- **replicaCount** : nombre de nœuds avec données (défaut : 2)
- **arbiter.enabled** : arbiter pour le quorum (défaut : true)
- **auth.rootPassword** : mot de passe admin MongoDB
- **auth.replicaSetKey** : clé partagée entre les membres du replica set
- **persistence.size** : taille du volume par nœud (défaut : 5Gi, total : 10Gi)
- **service.type** : NodePort 30017 pour accès externe
- **resources** : limites CPU/mémoire par nœud

## Accès

- **Depuis le cluster** : `mongodb-headless.mongodb.svc.cluster.local:27017`
- **Depuis l'extérieur** : `<NODE_IP>:30017`

Récupérer l'IP du master : `terraform output -raw k8s_master_floating_ip` (depuis `terraform/infra_platform`).

## Documentation complète

- [Guide d'utilisation](../../docs/MONGODB.md)
- [Cheatsheet](../../docs/MONGODB-CHEATSHEET.md)
