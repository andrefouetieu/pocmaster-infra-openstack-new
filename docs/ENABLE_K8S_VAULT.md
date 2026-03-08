# Activer Kubernetes Auth Method dans Vault

Guide pour configurer Vault (infra_platform) pour authentifier les pods du cluster Kubernetes (infra_app) via la méthode **kubernetes** auth.

---

## 0. Architecture

| Composant | Description |
|-----------|-------------|
| **infra_platform** | Cluster K8s + Vault (port 30200 NodePort) |
| **infra_app** | Cluster K8s des applications |
| **Réseaux** | Isolés — communication via IPs flottantes |

**⚠️ Important pour réseaux isolés :** Si infra_app utilise une IP flottante, le certificat TLS du serveur API K3s **doit inclure cette IP dans ses SANs**. Sinon, Vault ne peut pas valider les tokens (voir section Troubleshooting).

---

## 1. Prérequis

- Accès SSH aux masters des deux clusters
- Les deux clusters ont une IP flottante
- `kubectl` configuré pour accéder à au moins un cluster
- Vault déjà accessible et configuré (user/password ou token admin)

---

## Structure des étapes

Chaque étape indique où elle s'exécute :
- 🏗️ **[infra_platform]** : sur le master infra_platform (où tourne Vault)
- 🚀 **[infra_app]** : sur le master infra_app (le cluster des apps)

---

## 2. Étape 1 : Récupérer les paramètres du cluster infra_app

🚀 **[infra_app]**

### 2.1 Récupérer l'IP du master infra_app

Depuis ton poste local :

```bash
cd terraform/infra_app
APP_MASTER_IP=$(terraform output -raw k8s_master_floating_ip)
echo "IP flottante du master infra_app: $APP_MASTER_IP"
```

### 2.2 Se connecter au master infra_app

```bash
ssh -i ~/.ssh/id_rsa $(terraform output -raw vm_ssh_user)@$APP_MASTER_IP
```

### 2.3 Récupérer le certificat CA du cluster infra_app

Sur le master infra_app, copier le CA :

```bash
sudo cat /var/lib/rancher/k3s/server/tls/server-ca.crt
```

Copier tout le contenu et le sauvegarder localement dans `/tmp/app-cluster-ca.crt` (depuis ton poste).

### 2.4 Créer un ServiceAccount pour Vault

Sur le master infra_app (toujours en SSH) :

```bash
# Créer le ServiceAccount
kubectl create serviceaccount vault-auth -n default

# Assigner les droits au ServiceAccount (pour valider les tokens)
kubectl create clusterrolebinding vault-auth-binding \
    --clusterrole=system:auth-delegator \
    --serviceaccount=default:vault-auth
```

### 2.5 Générer le JWT du ServiceAccount

Sur le master infra_app :

```bash
kubectl create token vault-auth -n default --duration=87600h
```

**Copier le JWT affiché** (c'est une longue chaîne). Tu en auras besoin pour configurer Vault.

---

## 3. Étape 2 : Configurer Vault (infra_platform)

🏗️ **[infra_platform]**

### 3.1 Se connecter à Vault

Depuis ton poste, accéder à Vault et te connecter :

```bash
#recuperer l'ip de la plateforme
cd terraform/infra_platform
PLATFORM_MASTER_IP=$(terraform output -raw k8s_master_floating_ip)
echo "IP flottante du master infra_app: $PLATFORM_MASTER_IP"

#se connecter en ssh sur la platform 
ssh -i ~/.ssh/id_rsa $(terraform output -raw vm_ssh_user)@PLATFORM_MASTER_IP

# Via port-forward (depuis ta machine avec kubectl configuré)
kubectl port-forward -n vault svc/vault 30200:8200

# Ou accès direct si port 30200 est ouvert
export VAULT_ADDR=http://$PLATFORM_MASTER_IP:30200

# Connexion
vault login -method=userpass username=admin password=ton-mot-de-passe
```

### 3.2 Sauvegarder le CA localement

Créer un fichier `/tmp/app-cluster-ca.crt` avec le contenu du certificat CA copié à l'étape 2.3.

```bash
cat > /tmp/app-cluster-ca.crt <<EOF
-----BEGIN CERTIFICATE-----
<COLLER_LE_CONTENU_DU_CA_ICI>
-----END CERTIFICATE-----
EOF
```

### 3.3 Activer la méthode Kubernetes

```bash
vault auth enable kubernetes
```

(Si déjà activée, aucun problème.)

### 3.4 Configurer Vault avec les paramètres du cluster infra_app

```bash
vault write auth/kubernetes/config \
    kubernetes_host="https://<APP_MASTER_IP>:6443" \
    kubernetes_ca_cert=@/tmp/app-cluster-ca.crt \
    token_reviewer_jwt="<LE_JWT_COPIÉ_À_ÉTAPE_2.5>"

vault write auth/kubernetes/config \
    kubernetes_host="https://84.234.27.133:6443" \
    kubernetes_ca_cert=@/Users/mac/.crt/server-ca.infra-app.crt \
    token_reviewer_jwt="eyJhbGciOiJSUzI1NiIsImtpZCI6InpWVk9Nb0g5alNicGU0Y1Q2RXBJcWZaNlRYNHRJSFhIY0lad3Ixdm1WdUEifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjLmNsdXN0ZXIubG9jYWwiLCJrM3MiXSwiZXhwIjoyMDg3ODYzNDQyLCJpYXQiOjE3NzI1MDM0NDIsImlzcyI6Imh0dHBzOi8va3ViZXJuZXRlcy5kZWZhdWx0LnN2Yy5jbHVzdGVyLmxvY2FsIiwianRpIjoiZGFjMThkM2QtNDA3OC00NGViLTg1MTEtZTM1YjY1NGZkZDZlIiwia3ViZXJuZXRlcy5pbyI6eyJuYW1lc3BhY2UiOiJkZWZhdWx0Iiwic2VydmljZWFjY291bnQiOnsibmFtZSI6InZhdWx0LWF1dGgiLCJ1aWQiOiI4ZWQ3YmJlNi1kNDJiLTQxODEtYjA5OC00MGVhNjk0NGRiZTAifX0sIm5iZiI6MTc3MjUwMzQ0Miwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50OmRlZmF1bHQ6dmF1bHQtYXV0aCJ9.lnjU96as-itKUnKmP3P75_4qfox6zR-7ylwS5K3mt1iPq7Xo95pJ1gwcVglbv3eV5zAL1lSEM1JWXEIu_whGZxQ79PoSoQ9lGrczrvC4jeEZhyJx-a_9Hy5zmtRc2yGCPKx606kq4VBPwqMcxowhlClp2F4DzhThwt-j3-SwWEGJP5-lI04mK3Z8z88Tyv9t5ezfwQf7nCkJuY0Jfpkt2y4bITxhpbEEFc8ouGljtIfQffGfBV2-1AIe95W_Rb0Ijuy2n7xSXVRsSnj5BhV5BmQ2a2FHExsxKFJ5XDXhnGyfo2i7NFdkt9N4aRpMWSwgme3FP8BcEmRM30yJN49ztQ"    
```

**Remplacer :**
- `<APP_MASTER_IP>` : IP flottante du master infra_app
- `<LE_JWT_COPIÉ_À_ÉTAPE_2.5>` : Le JWT généré à l'étape 2.5

```bash
# Lire la configuration écrite
vault read auth/kubernetes/config
```

### 3.5 Créer une policy pour les pods

```bash
# Policy permettant aux pods de lire les secrets sous secret/data/app/*
vault policy write app-policy - <<EOF
path "secret/data/app/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/app/*" {
  capabilities = ["list"]
}
EOF
```

### 3.6 Créer un rôle Kubernetes dans Vault

```bash
vault write auth/kubernetes/role/app-role \
    bound_service_account_names=app-sa \
    bound_service_account_namespaces=default \
    policies=app-policy \
    ttl=1h
```

**Explication :**
- `bound_service_account_names=app-sa` : seul le ServiceAccount `app-sa` peut s'authentifier
- `bound_service_account_namespaces=default` : depuis le namespace `default`
- `audience="vault"` : vérifie que le JWT est destiné à Vault (sécurité supplémentaire)
- `policies=app-policy` : le pod reçoit la policy `app-policy`
- `ttl=1h` : le token a une durée de vie de 1 heure

---

## 4. Étape 3 : Préparer le cluster infra_app

🚀 **[infra_app]**

### 4.0 Clarification : les deux ServiceAccounts

Deux ServiceAccounts différents sont nécessaires dans **infra_app** :

```
┌─────────────────────────────────────────────────────────────┐
│ infra_app (cluster des applications)                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ServiceAccount: vault-auth (Étape 2.4)                     │
│  └─ Utilisé par: Vault (infra_platform)                     │
│  └─ Rôle: Valider les tokens des pods                       │
│  └─ Communication: Vault → infra_app                        │
│                                                              │
│  ServiceAccount: app-sa (Étape 4.1)                         │
│  └─ Utilisé par: Les pods de l'app                          │
│  └─ Rôle: S'authentifier à Vault                            │
│  └─ Communication: pod infra_app → Vault                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.1 Créer le ServiceAccount dans infra_app

Sur le master infra_app (ou via kubectl) :

```bash
kubectl create serviceaccount app-sa -n default
```

Ce ServiceAccount sera utilisé par les pods pour s'authentifier à Vault (différent de `vault-auth` créé à l'étape 2.4).

---

## 5. Étape 4 : Tester l'authentification

🚀 **[infra_app]**

### 5.1 Lancer un pod de test avec curl et le ServiceAccount app-sa

Récupérer d'abord l'IP flottante du master infra_platform :

```bash
cd terraform/infra_platform
VAULT_IP=$(terraform output -raw k8s_master_floating_ip)
echo "IP Vault: $VAULT_IP"
```

Puis lancer le test :

```bash
kubectl run -it --rm --image=curlimages/curl --restart=Never vault-test \
    --overrides='{"spec":{"serviceAccountName":"app-sa"}}' -- sh -c \
    'JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && curl -s --request POST --data "{\"jwt\": \"$JWT\", \"role\": \"app-role\"}" http://<VAULT_IP>:30200/v1/auth/kubernetes/login'
```

**Remplacer `<VAULT_IP>`** par l'IP flottante du master infra_platform (ex. `84.234.25.240`).

### 5.2 Résultat attendu

La réponse JSON contient :

```json
{
  "auth": {
    "client_token": "hvs.CAESIEfxKpPv3L6esFY8vxWGuT9BDeC5iLn-...",
    "policies": ["app-policy", "default"],
    "lease_duration": 3600,
    "metadata": {
      "role": "app-role",
      "service_account_name": "app-sa",
      "service_account_namespace": "default"
    }
  }
}
```

✅ Si tu obtiens un **`client_token`**, l'authentification Kubernetes fonctionne !

---

## 6. Tableau récapitulatif des valeurs

| Paramètre | Valeur | Récupération |
|-----------|--------|------------------|
| `kubernetes_host` | `https://<APP_MASTER_FLOATING_IP>:6443` | IP flottante du master infra_app (terraform output) |
| `kubernetes_ca_cert` | Contenu du CA | `/var/lib/rancher/k3s/server/tls/server-ca.crt` sur infra_app |
| `token_reviewer_jwt` | JWT long | `kubectl create token vault-auth -n default --duration=87600h` |
| `issuer` | (défaut K3s) | Laisser vide, K3s utilise `https://kubernetes.default.svc.cluster.local` |

---

## 7. Troubleshooting

### Erreur : "permission denied" lors du login Kubernetes

**Cause :** Le certificat TLS du serveur API d'infra_app ne contient pas l'IP flottante dans ses SANs.

🚀 **[infra_app]** — Vérification :

```bash
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt -noout -text | grep -A5 "Subject Alternative Name"
```

Si l'IP flottante (ex. `84.234.27.133`) **n'apparaît pas**, configurer le TLS SAN :

### Solution : Configurer le TLS SAN dans K3s

🚀 **[infra_app]** — Éditer le fichier service :

```bash
sudo nano /etc/systemd/system/k3s.service
```

Éditer le fichier pour que la section `ExecStart` ressemble à ceci (**remplacer `84.234.27.133` par ton IP flottante**) :

```ini
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=/etc/systemd/system/k3s.service.env
KillMode=process
Delegate=yes
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s \
    server \
    --tls-san=84.234.27.133

[Install]
WantedBy=multi-user.target
```

**Points importants :**
- La ligne `--tls-san=84.234.27.133` doit être **sur sa propre ligne**, après `server \`
- Remplacer `84.234.27.133` par l'IP flottante réelle d'infra_app

Sauvegarder : **Ctrl+X**, **Y**, **Enter**

Redémarrer K3s pour régénérer le certificat :

```bash
# Supprimer les anciens certificats
sudo rm -f /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt
sudo rm -f /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.key

# Recharger et redémarrer
sudo systemctl daemon-reload
sudo systemctl restart k3s

# Attendre la régénération (15-20 sec)
sudo sleep 20

# Vérifier que le SAN est bien présent
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/serving-kube-apiserver.crt -noout -text | grep -A5 "Subject Alternative Name"
```

Résultat attendu (avec l'IP flottante) :

```
X509v3 Subject Alternative Name: 
    DNS:kubernetes, DNS:kubernetes.default, ..., IP Address:84.234.27.133, ...
```

### Erreur : "unable to verify token"
- Vérifier que le JWT est valide et à jour
- Vérifier que `kubernetes_host` est accessible depuis le pod Vault
- Tester la connectivité : `nc -zv <APP_MASTER_IP> 6443`

### Erreur : "service account not found"
- Vérifier que le ServiceAccount `app-sa` existe : `kubectl get sa -n default`
- Vérifier que le pod utilise bien ce ServiceAccount (utiliser `--overrides='{"spec":{"serviceAccountName":"app-sa"}}'`)

### Vault ne peut pas accéder au cluster infra_app
- Vérifier que l'IP flottante est correcte
- Ouvrir le port 6443 dans le groupe de sécurité infra_app (si nécessaire)
- Tester depuis le pod Vault : `curl -k https://<APP_MASTER_IP>:6443/`

---

## 9. Références

- [Kubernetes Auth Method](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [Vault API - Kubernetes Auth](https://developer.hashicorp.com/vault/api-docs/auth/kubernetes)
