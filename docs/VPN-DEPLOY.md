# VPN (OpenVPN sur le master) — Déploiement et accès

Le **VPN** est installé **sur le nœud master** du cluster K8s lorsque `deploy_vpn = true`. Pas de VPS séparé.

---

## 1. Principe

- **deploy_vpn = true** : OpenVPN est installé sur le master du cluster
- Les clients se connectent à l’IP flottante du master (port 1194)
- Après connexion VPN, accès au réseau du cluster (kubectl, API K8s, etc.)
- Nécessite `k8s_master_floating_ip = true`

---

## 2. Variables

```hcl
deploy_vpn   = true
vpn_user_list = ["user1", "user2"]
k8s_master_floating_ip = true
```

---

## 3. Déploiement

```bash
cd terraform/infra_platform   # ou infra_app
cp terraform.tfvars.example terraform.tfvars
# Éditer : deploy_vpn = true, vpn_user_list = ["ton_user"]
terraform init && terraform apply
```

Terraform crée le cluster, installe K3s, puis OpenVPN sur le master et génère les fichiers `.ovpn` pour chaque utilisateur (récupérés sur la machine qui exécute Terraform).

---

## 4. Récupérer le .ovpn

Les fichiers `.ovpn` sont récupérés par Ansible (voir variable `vpn_destination_key` du rôle openvpn_client, par défaut `/tmp/` côté Ansible).

---

## 5. Accès SSH au master

- **User** : `vm_ssh_user` (défaut `ubuntu`)
- **Clé** : clé privée correspondant à `ssh_public_key_default_user`
- **IP** : `terraform output -raw k8s_master_floating_ip`

```bash
cd terraform/infra_platform
ssh -i ~/.ssh/id_rsa $(terraform output -raw vm_ssh_user)@$(terraform output -raw k8s_master_floating_ip)
```

---

## 6. OpenVPN Server vs Client

| | **OpenVPN Server** | **OpenVPN Client** |
|---|-------------------|---------------------|
| **Rôle** | Tourne **sur le master** du cluster. Écoute sur 1194 (UDP). | Le rôle Ansible **génère** les `.ovpn` et les **récupère** sur ta machine. |
| **Ansible** | Installe OpenVPN + easy-rsa sur le master, démarre le service. | Pour chaque `vpn_user_list` : génère un cert client, `.ovpn`, fetch vers ton poste. |
| **Utilisation** | Les clients se connectent avec leur `.ovpn` à l’IP du master. | Importer le `.ovpn` dans un client OpenVPN (Tunnelblick, etc.). |
