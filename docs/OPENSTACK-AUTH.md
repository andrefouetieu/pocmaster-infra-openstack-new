# Lier le provider OpenStack à ton compte (authentification)

Tu peux configurer l’authentification OpenStack **dans un fichier tfvars** (recommandé) ou via variables d’environnement / `clouds.yaml`.

---

## Méthode recommandée : terraform.tfvars

Les stacks **01_vpn** et **02_cluster** exposent des variables pour l’auth OpenStack et un bloc `provider "openstack"` qui les utilise.

1. Copier le fichier exemple :  
   `terraform/01_vpn/terraform.tfvars.example` → `terraform/01_vpn/terraform.tfvars`  
   (et idem pour `02_cluster` si tu utilises ce stack).

2. **Deux façons de remplir l’auth dans `terraform.tfvars` :**

   **A) Via clouds.yaml (recommandé si tu as le fichier téléchargé)**  
   - Dans `terraform.tfvars` : `openstack_cloud = "PCP-EJ4W6KP-dc3-a"` (ou `PCP-EJ4W6KP-dc4-a` pour l’autre région).  
   - C’est l’équivalent de `export OS_CLOUD=PCP-EJ4W6KP-dc3-a`, mais défini dans le tfvars.  
   - Si ton `clouds.yaml` est dans un emplacement non standard (ex. `~/.config/Infomaniak/clouds.yaml`), tu dois **exporter une seule fois** avant de lancer Terraform :  
     `export OS_CLOUD_CONFIG=~/.config/Infomaniak/clouds.yaml`  
   - Terraform ne peut pas définir `OS_CLOUD_CONFIG` dans le tfvars (c’est une variable d’environnement lue par le provider).

   **B) Via les variables openstack_***  
   - Laisser `openstack_cloud` vide et remplir :  
     `openstack_auth_url`, `openstack_username`, `openstack_password`, `openstack_project_name`, `openstack_region_name`, `openstack_user_domain_name`, `openstack_project_domain_name` (souvent `"default"`).

Le fichier `terraform.tfvars` est ignoré par Git ; ne pas le committer (il contient le mot de passe ou le nom du cloud). Les noms des variables et un exemple sont dans `terraform.tfvars.example` de chaque stack.

---

## project_domain_name / user_domain_name : à quoi correspond "default" ?

Dans OpenStack (Keystone), les **domaines** permettent de regrouper utilisateurs et projets. La valeur **`default`** (ou **`Default`**) désigne le **domaine par défaut** du cloud : c’est celui où sont créés la plupart des projets et utilisateurs quand aucun domaine spécifique n’est choisi.

- **`project_domain_name`** : le domaine qui **contient ton projet**. Si ton projet a été créé sans domaine particulier (cas habituel), il est dans le domaine `default` → tu mets **`default`** (ou **`Default`**, comme dans ton clouds.yaml).
- **`user_domain_name`** : le domaine qui **contient ton utilisateur**. Même logique : compte standard = domaine `default`.

**Faut-il changer ?** En général **non**. Si le `clouds.yaml` téléchargé indique `project_domain_name: default`, garde **`default`** dans tes tfvars. Tu ne changes que si ton fournisseur t’a créé un **domaine dédié** (ex. un nom d’organisation) et que ton projet ou utilisateur est dans ce domaine : dans ce cas, mets le **nom** de ce domaine à la place de `default`.

**En résumé** : `default` = domaine standard du cloud. On ne le change que si on t’a indiqué un autre domaine pour ton projet ou ton utilisateur.

---

## Régions (dc3-a, dc4-a)

Si la création de ton projet te donne accès à **deux régions** (ex. **dc3-a** et **dc4-a**), tu choisis **une** région par stack Terraform :

- Dans `terraform.tfvars` : `openstack_region_name = "dc3-a"` ou `openstack_region_name = "dc4-a"`.
- Toutes les ressources du stack (réseau, VMs, etc.) seront créées dans cette région. Pour utiliser l’autre région, il faudrait un autre stack avec l’autre valeur de `openstack_region_name`.

Le `clouds.yaml` téléchargé indique en général la région par défaut ; tu peux reprendre la même valeur pour rester cohérent avec la console.

---

## Méthode 2 : Variables d’environnement (CI / scripts)

Définis les variables suivantes **avant** de lancer `terraform plan` / `apply` (ou dans ton shell / ton CI).

### Variables minimales

| Variable | Description | Exemple |
|----------|-------------|--------|
| `OS_AUTH_URL` | URL du service Identity (Keystone) | `https://api.infomaniak.com/identity/v3` (à confirmer avec Infomaniak) |
| `OS_USERNAME` | Nom d’utilisateur OpenStack | ton login |
| `OS_PASSWORD` | Mot de passe | ton mot de passe |
| `OS_PROJECT_NAME` ou `OS_TENANT_NAME` | Nom du projet / tenant | nom du projet dans la console |
| `OS_REGION_NAME` | Région OpenStack | ex. `dc3` (voir la doc Infomaniak) |
| `OS_USER_DOMAIN_NAME` | Domaine utilisateur (si ton cloud utilise les domaines) | souvent `Default` |
| `OS_PROJECT_DOMAIN_NAME` | Domaine du projet (si utilisé) | souvent `Default` |

### Exemple en ligne de commande

```bash
export OS_AUTH_URL="https://api.infomaniak.com/identity/v3"
export OS_USERNAME="ton-email-ou-login"
export OS_PASSWORD="ton-mot-de-passe"
export OS_PROJECT_NAME="nom-du-projet"
export OS_REGION_NAME="dc3"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"

cd terraform/02_cluster
terraform plan
```

### Fichier `.env` (à ne pas committer)

Tu peux mettre ces `export` dans un fichier `.env` à la racine du repo ou dans `terraform/02_cluster/`, puis faire :

```bash
source .env
terraform plan
```

Ajoute `.env` dans ton `.gitignore` (déjà le cas si tu ignores `*.env` ou `.env`).

---

## Méthode 2 : Fichier `clouds.yaml`

C’est le même mécanisme que pour la CLI OpenStack (`openstack` / `nova`). Le provider Terraform le lit automatiquement.

### Emplacement du fichier

- Linux / macOS : `~/.config/openstack/clouds.yaml`
- Ou dans le répertoire courant (attention à ne pas le committer s’il contient des secrets)

### Exemple de contenu

```yaml
clouds:
  infomaniak:
    auth:
      auth_url: "https://api.infomaniak.com/identity/v3"
      username: "ton-email-ou-login"
      password: "ton-mot-de-passe"
      project_name: "nom-du-projet"
      user_domain_name: "Default"
      project_domain_name: "Default"
    region_name: "dc3"
```

Les valeurs (`auth_url`, `region_name`, etc.) sont à adapter selon la doc Infomaniak.

### Utiliser ce cloud avec Terraform

**Option 1 – Dans terraform.tfvars (recommandé)**  
Dans `terraform.tfvars` : `openstack_cloud = "PCP-EJ4W6KP-dc3-a"` (ou le nom de ton cloud dans `clouds.yaml`). Le provider utilisera ce nom ; pas besoin d’exporter `OS_CLOUD`.  
Si le fichier est hors emplacement standard (ex. `~/.config/Infomaniak/clouds.yaml`) :  
`export OS_CLOUD_CONFIG=~/.config/Infomaniak/clouds.yaml` avant de lancer Terraform.

**Option 2 – Variables d’environnement**

```bash
export OS_CLOUD=infomaniak
# Si clouds.yaml n’est pas dans ~/.config/openstack/ :
export OS_CLOUD_CONFIG=~/.config/Infomaniak/clouds.yaml
cd terraform/02_cluster
terraform plan
```

Le provider lit soit la variable Terraform `openstack_cloud` (depuis tfvars), soit `OS_CLOUD` ; avec `openstack_cloud` dans tfvars, tu n’as pas besoin de `OS_CLOUD`.

---

## Où trouver les bonnes valeurs (Infomaniak)

- **URL d’auth, région, noms de domaine** : documentation OpenStack / cloud Infomaniak, ou dans la console web Infomaniak (section OpenStack / API / accès).
- **Projet** : nom du projet dans la console (souvent lié à ton compte ou à un sous-projet).
- **Identifiants** : ceux de ton compte Infomaniak (ou un utilisateur OpenStack dédié si le cloud le propose).

Si Infomaniak fournit un fichier `clouds.yaml` ou un exemple d’`openrc`, tu peux t’en inspirer pour remplir `OS_*` ou `clouds.yaml`.

---

## Vérifier que ça fonctionne

Après avoir configuré env vars ou `clouds.yaml` + `OS_CLOUD` :

```bash
cd terraform/02_cluster
terraform plan
```

Si le provider arrive à s’authentifier, le plan s’exécute (éventuellement avec des erreurs de config réseau / quotas, mais pas d’erreur d’auth). Une erreur du type `401 Unauthorized` ou `Could not find endpoint` indique une mauvaise URL, un mauvais projet/région ou des identifiants incorrects.

---

## Résumé

| Méthode | Quand l’utiliser |
|---------|-------------------|
| **Variables `OS_*`** | CI/CD, scripts, ou quand tu ne veux pas de fichier de config. |
| **`clouds.yaml` + `OS_CLOUD`** | Usage local, même config que la CLI OpenStack. |

Dans les deux cas, **ne committe jamais** mots de passe ou secrets (utilise des variables d’environnement ou un fichier ignoré par Git).
