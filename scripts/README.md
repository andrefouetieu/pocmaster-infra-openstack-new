# Scripts — Manuel d'utilisation

Scripts pour configurer l'intégration **Vault / Kubernetes Auth** entre les clusters `infra_platform` (Vault) et `infra_app` (applications).

---

## Dépendances globales

- `bash` (4+)
- `jq`
- `curl`

Les scripts spécifiques demandent en plus : `vault`, `kubectl`, `openssl` selon le cas.

---

## Ordre d'exécution

1. **setup-app-cluster.sh** — à exécuter sur le **master infra_app**
2. **enable-vault-k8s.sh** — à exécuter depuis ta machine (ou infra_platform), avec la config générée par le script 1

---

# setup-app-cluster.sh

Prépare le cluster **infra_app** pour l’authentification Vault : TLS SAN, ServiceAccounts, JWT, CA.

**Où l’exécuter :** sur le master du cluster infra_app (directement ou via SSH).

**Dépendances :** `jq`, `kubectl`, `openssl`, `sudo`

### Options

| Option     | Description                                                |
|------------|------------------------------------------------------------|
| `--config` | Fichier de configuration JSON (obligatoire)               |
| `--dry-run`| Affiche les actions sans les exécuter                     |
| `--skip-k3s` | Ne modifie pas k3s.service (si TLS SAN déjà configuré)  |
| `--help`   | Affiche l’aide                                            |

### Fichier de configuration

Copier le template et adapter les valeurs :

```bash
cp scripts/config-app.example.json scripts/config-app.json
```

| Champ | Description | Exemple |
|-------|-------------|---------|
| `floating_ip` | IP flottante du master infra_app | `84.234.27.133` |
| `kubernetes.namespace` | Namespace Kubernetes | `default` |
| `kubernetes.sa_token_reviewer` | SA utilisé par Vault pour valider les tokens | `vault-auth` |
| `kubernetes.sa_token_reviewer_binding` | Nom du ClusterRoleBinding | `vault-auth-binding` |
| `kubernetes.sa_app` | SA utilisé par les pods pour s’auth à Vault | `app-sa` |
| `kubernetes.jwt_duration` | Durée du JWT token reviewer | `87600h` |
| `k3s.service_file` | Chemin du fichier systemd K3s | `/etc/systemd/system/k3s.service` |
| `output.ca_cert_local_path` | Où sauvegarder le CA cert | `/tmp/app-cluster-ca.crt` |
| `output.vault_config_output` | Fichier JSON produit pour enable-vault-k8s | `/tmp/vault-config-values.json` |

### Actions réalisées

1. Vérifie si l’IP flottante est déjà dans le SAN du certificat kube-apiserver
2. Modifie `/etc/systemd/system/k3s.service` pour ajouter `--tls-san=<floating_ip>`
3. Supprime les anciens certs, redémarre K3s, attend la régénération
4. Vérifie que le SAN contient bien l’IP flottante
5. Crée le ServiceAccount `vault-auth` + ClusterRoleBinding `system:auth-delegator`
6. Génère le JWT du SA `vault-auth`
7. Crée le ServiceAccount `app-sa`
8. Exporte le CA cert vers le chemin configuré
9. Génère un fichier JSON prêt à être complété pour `enable-vault-k8s.sh`

### Exemples

```bash
# Exécution directe sur le master infra_app
./scripts/setup-app-cluster.sh --config scripts/config-app.json

# Si TLS SAN déjà configuré (évite le redémarrage K3s)
./scripts/setup-app-cluster.sh --config scripts/config-app.json --skip-k3s

# Dry-run pour prévisualiser les actions
./scripts/setup-app-cluster.sh --config scripts/config-app.json --dry-run

# Depuis ta machine via SSH
scp scripts/config-app.json user@<APP_MASTER_IP>:/tmp/
ssh user@<APP_MASTER_IP> './scripts/setup-app-cluster.sh --config /tmp/config-app.json'
```

### Sortie

- **`/tmp/app-cluster-ca.crt`** (ou chemin configuré) : certificat CA du cluster
- **`/tmp/vault-config-values.json`** (ou chemin configuré) : fichier à compléter pour `enable-vault-k8s.sh` (JWT et CA déjà renseignés)

---

# enable-vault-k8s.sh

Configure Vault sur **infra_platform** : unseal, superadmin, auth Kubernetes, policies et rôles.

**Où l’exécuter :** depuis ta machine locale (avec accès réseau à Vault) ou depuis tout host ayant accès à Vault et au fichier CA.

**Dépendances :** `vault`, `jq`, `curl`

### Options

| Option     | Description                              |
|------------|------------------------------------------|
| `--config` | Fichier de configuration JSON (obligatoire) |
| `--dry-run`| Affiche les actions sans les exécuter    |
| `--help`   | Affiche l’aide                           |

### Fichier de configuration

Copier le template et remplir les champs sensibles :

```bash
cp scripts/config.example.json scripts/config.json
```

| Champ | Description | Exemple |
|-------|-------------|---------|
| `vault.addr` | URL de Vault | `http://84.234.25.240:30200` |
| `vault.unseal_key` | Clé d’unseal (1 clé si threshold=1) | `abcd1234...` |
| `vault.root_token` | Token root Vault | `hvs.xxx...` |
| `superadmin.username` | User superadmin à créer | `superadmin` |
| `superadmin.password` | Mot de passe superadmin (optionnel) | `MotDePasse123` |
| `kubernetes.host_ip` | IP flottante du master infra_app | `84.234.27.133` |
| `kubernetes.ca_cert_path` | Chemin vers le CA cert (ex. `/tmp/app-cluster-ca.crt`) | |
| `kubernetes.jwt` | JWT du SA token reviewer | généré par setup-app-cluster.sh |
| `kubernetes.namespace` | Namespace Kubernetes | `default` |
| `kubernetes.sa_token_reviewer` | Nom du SA token reviewer | `vault-auth` |
| `kubernetes.sa_app` | Nom du SA utilisé par les apps | `app-sa` |
| `vault_role.name` | Nom du rôle Vault | `app-role` |
| `vault_role.policy` | Nom de la policy | `app-policy` |
| `vault_role.ttl` | TTL du token Vault | `1h` |

### Actions réalisées

1. Vérifie que Vault est accessible
2. Unseal Vault avec la clé fournie (1 clé si threshold=1)
3. Valide le root token
4. Crée un user superadmin (userpass, policy équivalente root)
5. Active l’auth method `kubernetes`
6. Configure `auth/kubernetes/config` (host, CA, JWT)
7. Crée la policy `app-policy` (`secret/data/app/*`, `secret/metadata/app/*`)
8. Crée le rôle Kubernetes lié au SA `app-sa`

### Exemples

```bash
# Exécution standard
./scripts/enable-vault-k8s.sh --config scripts/config.json

# Utiliser le fichier généré par setup-app-cluster.sh (après complétion)
./scripts/enable-vault-k8s.sh --config /tmp/vault-config-values.json

# Dry-run
./scripts/enable-vault-k8s.sh --config scripts/config.json --dry-run
```

### Workflow complet

```bash
# 1. Sur le master infra_app
./scripts/setup-app-cluster.sh --config scripts/config-app.json

# 2. Récupérer les fichiers et compléter la config
scp user@<APP_IP>:/tmp/app-cluster-ca.crt /tmp/
scp user@<APP_IP>:/tmp/vault-config-values.json /tmp/
# Éditer vault-config-values.json : ajouter VAULT_IP, unseal_key, root_token, superadmin password

# 3. Depuis ta machine
./scripts/enable-vault-k8s.sh --config /tmp/vault-config-values.json
```

---

## Sécurité

- **Ne pas versionner** `config.json` ni `config-app.json` s’ils contiennent des secrets
- Ajouter à `.gitignore` : `scripts/config.json`, `scripts/config-app.json`
- Les fichiers `.example.json` sont des modèles sans secrets réels

---

## Références

- [Activer Kubernetes Auth Method dans Vault](../docs/ENABLE_K8S_VAULT.md)
