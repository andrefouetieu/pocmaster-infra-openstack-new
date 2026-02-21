# Gestion des Terraform states

Ce projet a **deux stacks Terraform** avec des backends différents. Chaque stack a son propre state (fichier d’état).

---

## Où sont stockés les states ?

| Stack        | Dossier              | Backend        | Stockage du state                          |
|-------------|----------------------|----------------|--------------------------------------------|
| **VPN**     | `terraform/01_vpn/`  | `http`         | GitLab (API HTTP, projet 61352701)         |
| **Cluster** | `terraform/02_cluster/` | `s3`        | AWS S3 + DynamoDB (verrouillage)           |

- **01_vpn** : state et lock gérés par GitLab. Il faut les droits sur le projet et, si besoin, un token pour l’API.
- **02_cluster** : state dans un bucket S3, lock dans une table DynamoDB. Il faut un compte AWS et les credentials (variables d’environnement ou `~/.aws/credentials`).

---

## Initialiser le backend (state)

### 01_vpn (GitLab)

```bash
cd terraform/01_vpn
terraform init
```

Aucun fichier de config backend à fournir : tout est dans `00_providers.tf`. Si GitLab exige une auth, configurer le token (variable d’environnement ou outil prévu par GitLab pour le backend HTTP).

### 02_cluster (AWS S3 + DynamoDB)

**Si le bucket S3 et la table DynamoDB existent déjà** : ne rien créer. Renseigner dans `backend.s3.hcl` le **nom du bucket** et le **nom de la table** DynamoDB existants, puis lancer `terraform init -reconfigure -backend-config=backend.s3.hcl`. Terraform utilisera ces ressources telles quelles.

**Si tu crées les ressources pour la première fois** : voir les commandes dans `terraform/02_cluster/backend.s3.example.hcl`.

1. Créer le bucket S3 et la table DynamoDB (une fois) si besoin : voir `backend.s3.example.hcl`.
2. Copier `backend.s3.example.hcl` en `backend.s3.hcl`, renseigner `bucket`, `region`, `dynamodb_table` (noms existants ou venant d’être créés).
3. Configurer les credentials AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` ou `~/.aws/credentials`).
4. Initialiser avec le backend :

```bash
cd terraform/02_cluster
terraform init -reconfigure -backend-config=backend.s3.hcl
```

Ne pas committer `backend.s3.hcl` (fichier ignoré par Git).

---

## Commandes utiles pour le state

À exécuter **dans le dossier du stack** concerné (`01_vpn` ou `02_cluster`).

| Commande | Rôle |
|----------|------|
| `terraform state list` | Lister les ressources dans le state. |
| `terraform state show <adresse>` | Afficher une ressource (ex. `module.k8s_master.openstack_compute_instance_v2.instance[0]`). |
| `terraform state pull` | Télécharger le state en JSON (sauvegarde ou inspection). |
| `terraform state push <fichier>` | Remplacer le state distant par un fichier local (à utiliser avec précaution). |
| `terraform state rm <adresse>` | Retirer une ressource du state (sans la détruire dans le cloud). |
| `terraform state mv <src> <dst>` | Renommer/déplacer une ressource dans le state. |

**Sauvegarde du state** (avant opération risquée) :

```bash
terraform state pull > backup-state-$(date +%Y%m%d).json
```

---

## Verrouillage (lock)

- **01_vpn** : le backend `http` utilise le lock GitLab (automatique).
- **02_cluster** : le backend S3 utilise la table DynamoDB pour le lock. Tant que `terraform apply` (ou `plan` avec lock) tourne, un autre `apply` sur le même state attendra ou échouera avec une erreur de lock.

En cas de **lock resté bloqué** (crash, interruption) :

- **GitLab** : déverrouiller via l’interface ou l’API GitLab du projet.
- **S3 + DynamoDB** : supprimer l’entrée correspondante dans la table `terraform-state-lock` (clé = l’ID du state utilisé par Terraform).

---

## Bonnes pratiques

1. **Ne jamais committer** le state (ni `terraform.tfstate`, ni les backups) : il peut contenir des secrets. Les backends le stockent à distance.
2. **Ne pas lancer deux `terraform apply`** en parallèle sur le même stack (risque de state corrompu si pas de lock, ou d’échec de lock).
3. **Sauvegarder le state** avant un `state rm` / `state push` / migration : `terraform state pull > backup.json`.
4. **02_cluster** : garder le bucket S3 avec **versioning** activé pour pouvoir récupérer une ancienne version du state si besoin.
5. **Backend 02_cluster** : garder `backend.s3.hcl` hors du dépôt (déjà dans `.gitignore`) et ne partager que `backend.s3.example.hcl`.

---

## Changer de backend (migration)

Pour passer un stack d’un backend à un autre (ex. GitLab → S3) :

1. Configurer le **nouveau** backend dans le bloc `backend` (ou dans un fichier `-backend-config`).
2. Lancer `terraform init -migrate-state` (ou `-reconfigure` selon le cas). Terraform propose de copier l’état existant vers le nouveau backend.
3. Vérifier avec `terraform state list` et un `terraform plan` (aucun changement attendu).

Faire une **sauvegarde** du state avant (`terraform state pull`) et s’assurer qu’aucun autre processus n’utilise le state pendant la migration.
