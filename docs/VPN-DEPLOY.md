# VPN (Terraform + Ansible) — Déploiement et accès

Ce document couvre uniquement la partie **VPN** (Terraform `01_vpn` + Ansible). La partie Consul (`02_infrastructure`) n’est pas traitée ici.

---

## 1. Variables sensibles (utilisation sécurisée)

### Terraform

- **À ne pas committer** : clé SSH, valeurs spécifiques à ton environnement.
- **Méthode recommandée** : utiliser un fichier `terraform.tfvars` (ignoré par Git) et/ou des variables d’environnement.

**Mise en place :**

```bash
cd terraform/01_vpn
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars et remplir au minimum :
# - ssh_public_key_default_user = "contenu de ta clé publique" (ex: $(cat ~/.ssh/id_rsa.pub))
# - vpn_user_list, network_* si différent des exemples
```

**Alternative (sans fichier sur disque) :**

```bash
export TF_VAR_ssh_public_key_default_user="$(cat ~/.ssh/id_rsa.pub)"
export TF_VAR_vpn_user_list='["user1","user2"]'
# Puis terraform plan / apply
```

La variable `ssh_public_key_default_user` est marquée `sensitive = true` dans Terraform, donc elle ne s’affiche pas en clair dans les logs.

### Ansible

- Les variables sensibles (ex. `ansible/envs/dev/group_vars/openvpn.yml`) peuvent être chiffrées avec **Ansible Vault** :
  - `ansible-vault encrypt ansible/envs/dev/group_vars/openvpn.yml`
  - Lancer les playbooks avec `--ask-vault-pass` ou un fichier mot de passe.
- Pour les runs lancés par Terraform, l’inventaire et les options sont générés dans `05_ansible.tf` (user `xavki`, clé `~/.ssh/id_rsa`) : s’assurer que cette clé correspond à celle utilisée dans `ssh_public_key_default_user`.

---

## 2. Lancer le déploiement Terraform (VPN)

### Prérequis

- Terraform >= 0.14
- Provider OpenStack configuré (credentials Infomaniak : variables d’environnement ou `clouds.yaml`)
- Ansible installé
- Accès SSH avec la clé dont la **publique** est dans `ssh_public_key_default_user` (par défaut dans les scripts : user `xavki`, clé `~/.ssh/id_rsa`)

### Étapes

```bash
cd terraform/01_vpn

# 1. Variables : au moins ssh_public_key_default_user (tfvars ou TF_VAR_*)
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars

# 2. Init (télécharge providers + configure le backend state)
terraform init

# 3. Vérifier le plan
terraform plan

# 4. Appliquer (crée réseau, VM, security groups, puis lance Ansible après ~20 s)
terraform apply
```

À la fin de `apply`, Terraform aura :

- Créé la VM OpenVPN avec une IP flottante
- Lancé le playbook **openvpn_server** (installation et configuration du serveur)
- Pour chaque entrée de `vpn_user_list`, lancé **openvpn_client** et récupéré le fichier `.ovpn` sur la machine où tu exécutes Terraform (par défaut dans `/tmp/` côté Ansible, voir variable `vpn_destination_key` du role client)

---

## 3. Accéder au serveur (SSH)

- **User** : `xavki` (défini dans le module instance, cloud-init)
- **Clé** : la clé **privée** correspondant à `ssh_public_key_default_user` (dans les scripts Terraform : `~/.ssh/id_rsa`)
- **IP** : l’IP flottante de la VM. Pour la récupérer :

```bash
cd terraform/01_vpn
terraform output
# ou
terraform output -json
```

Les outputs sont définis dans `06_outputs.tf`. Connexion SSH :

```bash
ssh -i ~/.ssh/id_rsa xavki@$(terraform output -raw openvpn_floating_ip)
```

(Adapter le chemin de la clé si tu utilises une autre clé que `~/.ssh/id_rsa`.)

---

## 4. Différence entre OpenVPN Server et OpenVPN Client (dans ce repo)

| | **OpenVPN Server** | **OpenVPN Client** |
|---|-------------------|---------------------|
| **Rôle** | Tourne **sur la VM** dans le cloud. Écoute sur le port 1194 (UDP/TCP), gère les connexions des clients. | **Ne tourne pas** sur la VM en tant que service : le role Ansible **génère** les fichiers de configuration client (certificats + `.ovpn`) et les **récupère** sur ta machine. |
| **Ce que fait Ansible** | Installe OpenVPN + easy-rsa, crée la CA, le certificat serveur, la config serveur, iptables, démarre `openvpn@server`. | Pour chaque utilisateur dans `vpn_user_list` : génère un certificat client, construit un fichier `.ovpn` (tout-en-un) et le **fetch** vers ton poste (`vpn_destination_key`, ex. `/tmp/`). |
| **Où ça s’exécute** | Sur l’hôte **openvpn** (la VM). | Les tâches Ansible s’exécutent **sur la VM** (génération des certs et du `.ovpn`), puis le **fetch** télécharge le `.ovpn` vers la machine qui lance Ansible (ton PC). |
| **Utilisation** | Une fois le serveur en place, les clients (toi ou d’autres) utilisent le fichier `.ovpn` dans un logiciel OpenVPN (client desktop, Tunnelblick, etc.) pour se connecter **au** serveur. | Le fichier `.ovpn` récupéré est à importer dans un **client OpenVPN** sur ton poste (ou à envoyer de façon sécurisée à un autre utilisateur). |

En résumé : **openvpn_server** = installer et configurer le serveur VPN sur la VM ; **openvpn_client** = créer les comptes clients (certificats + fichier `.ovpn`) et te les ramener sur ta machine pour te connecter au serveur.
