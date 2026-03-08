# HashiCorp Vault — Guide d’utilisation

Vault est installé via Helm sur le cluster K8s (infra_platform) et exposé en NodePort **30200**.

---

## 1. Accès à Vault

### Option A : Port-forward (kubectl)

Si le port 30200 n'est pas accessible (sécurité réseau, firewall) ou pour tester sans ouvrir le NodePort : utiliser **kubectl port-forward** depuis une machine où `kubectl` pointe vers le cluster.

```bash


# Récupérer le kubeconfig d'abord (depuis terraform/infra_platform)
MASTER_IP=$(terraform output -raw k8s_master_floating_ip)

# dans la vm
kubectl port-forward -n vault svc/vault 30200:8200

ssh -i ~/.ssh/id_rsa $(terraform output -raw vm_ssh_user)@$MASTER_IP

# Lancer le port-forward (garde le terminal ouvert)
sudo kubectl port-forward -n vault svc/vault 30200:8200
```

Puis accéder à :
- **UI** : http://127.0.0.1:8200/ui
- **API** : http://127.0.0.1:8200

```bash
export VAULT_ADDR=http://$MASTER_IP:8200
vault status
```

### Option B : Accès direct (NodePort)

| Accès | URL |
|-------|-----|
| **UI** | `http://<MASTER_IP>:30200/ui` |
| **API** | `http://<MASTER_IP>:30200` |

Récupérer l’IP du master :
```bash
cd terraform/infra_platform
terraform output -raw k8s_master_floating_ip
```

### Via l’interface web

1. Ouvrir `http://<MASTER_IP>:30200/ui`
2. Premier accès : **Initialize** Vault, sauvegarder les **unseal keys** et le **root token**
3. Se connecter avec le root token (à remplacer par user/password en prod)

### Via le CLI (local)

```bash
# Installer le CLI (macOS)
brew install vault

# Configurer l’adresse
export VAULT_ADDR=http://<MASTER_IP>:30200
export VAULT_ADDR=http://84.234.24.104:30200

# Connexion avec token
vault login

# Connexion avec user/password (une fois userpass activé)
vault login -method=userpass username=admin password=ton-mot-de-passe
```

---

## 2. Commandes Vault de base

### Statut et santé

```bash
vault status
vault token lookup
```

### Secrets KV v2 (exemple)

```bash
# Activer le secret engine KV v2
vault secrets enable -path=secret kv-v2

# Écrire un secret
vault kv put secret/myapp/config username="admin" password="xxx"

# Lire un secret
vault kv get secret/myapp/config

# Lister les clés
vault kv list secret/
```

### Policies

```bash
# Lister les policies
vault policy list

# Lire une policy
vault policy read default

# Créer une policy
vault policy write mon-app - <<EOF
path "secret/data/mon-app/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

---

## 3. Authentification User/Password

### 3.1 Activer la méthode userpass

```bash
# Via CLI (connecté avec root token)
vault auth enable userpass
```

Ou via l’UI : **Access** → **Auth Methods** → **Enable new method** → **Username**.

### 3.2 Créer un utilisateur

```bash
# Utilisateur avec la policy default
vault write auth/userpass/users/iyadris \
    password=IyadrisVault \
    policies=admin

# Utilisateur avec une policy custom
vault write auth/userpass/users/developpeur \
    password=AutreMotDePasse \
    policies=mon-app
```

### 3.3 Créer plusieurs utilisateurs

```bash
# Utilisateur 1
vault write auth/userpass/users/alice \
    password=AlicePwd123 \
    policies=admin

# Utilisateur 2
vault write auth/userpass/users/bob \
    password=BobPwd456 \
    policies=default

# Utilisateur 3 avec policy dédiée
vault write auth/userpass/users/ops \
    password=OpsPwd789 \
    policies=admin
```

### 3.4 Modifier un mot de passe

```bash
vault write auth/userpass/users/admin \
    password=NouveauMotDePasse \
    policies=default
```

### 3.5 Supprimer un utilisateur

```bash
vault delete auth/userpass/users/admin
```

### 3.6 Connexion avec user/password

**Via l’UI :**
- Choisir la méthode **Username**
- Saisir le username et le mot de passe

**Via le CLI :**\
```bash
vault login -method=userpass username=admin password=AdminPwd
```

### 3.7 Policy admin (droits étendus)

```bash
# Via CLI (connecté avec root token)
vault auth enable userpass

vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

vault write auth/userpass/users/admin \
    password=AdminPwd \
    policies=admin
```

---

## 4. Single Sign-On (SSO)

Vault supporte plusieurs méthodes SSO : **OIDC**, **JWT**, **SAML**, **LDAP**.

### 4.1 OIDC (OpenID Connect)

Pour intégrer Google, GitHub, Okta, Keycloak, etc.

```bash
vault auth enable oidc

vault write auth/oidc/config \
    oidc_discovery_url="https://accounts.google.com" \
    oidc_client_id="votre-client-id" \
    oidc_client_secret="votre-client-secret" \
    default_role="default"

vault write auth/oidc/role/default \
    user_claim="sub" \
    groups_claim="groups" \
    policies="default" \
    ttl=1h
```

**UI :** Sur la page de login, choisir **OIDC** et rediriger vers le fournisseur.

### 4.2 JWT

Pour des JWTs émis par un IdP (Auth0, Keycloak, etc.) :

```bash
vault auth enable jwt

vault write auth/jwt/config \
    oidc_discovery_url="https://votre-tenant.auth0.com/" \
    oidc_discovery_ca_pem=@/path/to/ca.pem

vault write auth/jwt/role/app \
    role_type="jwt" \
    user_claim="sub" \
    bound_audiences="https://api.votre-app.com" \
    policies="default" \
    ttl=1h
```

### 4.3 SAML

Pour un IdP SAML (Azure AD, Okta SAML, etc.) :

```bash
vault auth enable saml

vault write auth/saml/config \
    idp_metadata_url="https://login.microsoftonline.com/xxx/federationmetadata/2007-06/federationmetadata.xml" \
    idp_ca_certs=@/path/to/ca.pem

vault write auth/saml/role/azure-users \
    idp_metadata_url="https://login.microsoftonline.com/xxx/federationmetadata/2007-06/federationmetadata.xml" \
    bound_attributes=email \
    policies=default
```

---

## 5. Active Directory

### 5.1 Prérequis

- Accès LDAP/LDAPS au serveur Active Directory
- Compte service avec droits de lecture (pour Vault)
- Groupes AD utilisés pour les policies

### 5.2 Activer et configurer

```bash
vault auth enable ldap

vault write auth/ldap/config \
    url="ldaps://ad.example.com" \
    userdn="OU=Users,DC=example,DC=com" \
    userattr="sAMAccountName" \
    groupdn="OU=Groups,DC=example,DC=com" \
    groupattr="memberOf" \
    binddn="CN=vault-svc,OU=ServiceAccounts,DC=example,DC=com" \
    bindpass="MotDePasseDuCompteService" \
    insecure_tls=false \
    certificate=@ad-ca.pem
```

### 5.3 Associer des groupes AD à des policies

```bash
# Le groupe AD "Vault-Admins" obtient la policy admin
vault write auth/ldap/groups/Vault-Admins policies=admin

# Le groupe "App-Developers" obtient la policy mon-app
vault write auth/ldap/groups/App-Developers policies=mon-app
```

### 5.4 Connexion d’un utilisateur AD

```bash
# Via CLI
vault login -method=ldap username=jean.dupont password=SonMotDePasseAD

# Via UI : méthode LDAP, puis identifiants AD
```

---

## 6. Tableau récapitulatif des méthodes d’auth

| Méthode   | Cas d’usage                    | Complexité |
|-----------|---------------------------------|------------|
| **Token** | Dev, scripts, CI/CD            | Faible     |
| **Userpass** | Équipe petite, quelques users | Faible     |
| **LDAP/AD** | Entreprise avec AD            | Moyenne    |
| **OIDC**  | SSO Google, GitHub, Okta       | Moyenne    |
| **SAML**  | Entreprise (Azure AD, Okta)    | Élevée     |
| **JWT**   | Apps, API, microservices       | Moyenne    |

---

## 7. Bonnes pratiques

1. **Ne pas utiliser le root token** en usage courant : créer un admin via userpass et révoquer/limiter le root token
2. **Activer l’audit** : `vault audit enable file file_path=/var/log/vault_audit.log`
3. **TTL raisonnables** : éviter les tokens avec TTL trop longs
4. **Policies restrictives** : principe du moindre privilège
5. **Rotation des secrets** : utiliser les engines dynamiques (DB, AWS, etc.) quand possible

---

## 8. Références

- [Vault Auth Methods](https://developer.hashicorp.com/vault/docs/auth)
- [Userpass Auth](https://developer.hashicorp.com/vault/docs/auth/userpass)
- [LDAP Auth](https://developer.hashicorp.com/vault/docs/auth/ldap)
- [OIDC Auth](https://developer.hashicorp.com/vault/docs/auth/jwt)
