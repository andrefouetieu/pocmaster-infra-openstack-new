# Infras — infra_platform, infra_app

Les infras Terraform créent des clusters Kubernetes sur OpenStack Infomaniak. Chaque infra est un dossier autonome avec son état Terraform et ses variables.

---

## 1. Infras disponibles

| Infra | Description | CIDR cluster |
|-------|-------------|--------------|
| **infra_platform** | Cluster K8s pour outils plateforme (Vault, Kafka, etc.) | 10.0.10.0/24 |
| **infra_app** | Cluster K8s dédié aux applications | 10.0.20.0/24 |

---

## 2. Options (communes)

| Variable | Type | Défaut | Description |
|----------|------|--------|-------------|
| `deploy_vpn` | bool | `false` | Installer OpenVPN **sur le master** (accès cluster via VPN) |
| `deploy_k8s` | bool | `true` | Créer un cluster K8s (1 master + N workers) |
| `install_vault` | bool | `false` | (infra_platform) Installer Vault via Helm après création du cluster |

**deploy_vpn** : le VPN s’installe sur le nœud master du cluster. Les clients se connectent à l’IP du master pour joindre le réseau du cluster. Requiert `k8s_master_floating_ip = true`.

### Variables principales

- `infra_name` : nom de l’infra (préfixe des ressources)
- `ssh_public_key_default_user` : clé SSH publique (sensitive)
- `cluster_subnet_cidr` : CIDR du subnet cluster
- `k8s_worker_count` : nombre de workers
- `vpn_user_list` : utilisateurs pour les certificats .ovpn (si deploy_vpn)

---

## 3. Utilisation

### infra_platform

Cluster pour outils plateforme (Vault, Kafka, etc.). 1 worker par défaut.  
Avec `install_vault = true` : Vault est installé automatiquement via Helm après apply. Sinon : `cd ../../tools/vault && ./install.sh`

```bash
cd terraform/infra_platform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

### infra_app

Cluster dédié aux applications. 2 workers par défaut.

```bash
cd terraform/infra_app
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
# Déployer les apps via Helm ou kubectl
```

### Avec VPN (accès sécurisé)

```hcl
deploy_vpn   = true
vpn_user_list = ["user1", "user2"]
k8s_master_floating_ip = true
```

---

## 4. Flux de travail

1. Choisir l’infra : infra_platform ou infra_app
2. `cp terraform.tfvars.example terraform.tfvars` et remplir `ssh_public_key_default_user`
3. `terraform init && terraform apply`
4. Récupérer le kubeconfig (master), installer les tools depuis `tools/`

---

## 5. Outputs (communs)

| Output | Condition | Description |
|--------|-----------|-------------|
| `k8s_master_floating_ip` | deploy_k8s | IP du master (point d’accès VPN si deploy_vpn) |
| `k8s_master_internal_ip` | deploy_k8s | IP interne du master |
| `vm_ssh_user` | toujours | User SSH |
