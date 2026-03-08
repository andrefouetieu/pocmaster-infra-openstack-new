# infra-openstack

Déploiement sur le cloud Infomaniak (OpenStack) avec **Terraform** et **Ansible** :

- **infra_platform** : cluster K8s pour outils plateforme (Vault, Kafka, etc.)
- **infra_app** : cluster K8s dédié aux applications
- **deploy_vpn** : installer OpenVPN sur le master (accès cluster via VPN)
- **tools/** : charts Helm (Vault, etc.) à installer manuellement sur un cluster créé

---

## Prérequis

- **Terraform** >= 0.14
- **Ansible**
- Compte **Infomaniak** (OpenStack) et credentials configurés (variables d'environnement ou `clouds.yaml`)
- Clé SSH (publique fournie à Terraform, privée pour se connecter aux VMs)

Installation des collections Ansible (pour le rôle openvpn_server) :

```bash
cd ansible && ansible-galaxy collection install -r requirements.yml
```

---

## Structure du dépôt

```
.
├── ansible/
│   ├── openvpn_server.yml      # OpenVPN sur le master
│   ├── openvpn_client.yml      # Génère les .ovpn
│   ├── k8s_cluster.yml         # K3s (master + workers)
│   └── roles/...
├── terraform/
│   ├── infra_platform/         # Cluster plateforme (Vault, Kafka, etc.)
│   ├── infra_app/              # Cluster dédié applications
│   └── modules/
│       ├── vps/                # Module VPS (optionnel, non utilisé par défaut)
│       ├── cluster/            # Cluster K3s + OpenVPN sur master
│       ├── instance/
│       └── network/
├── tools/
│   ├── README.md
│   └── vault/
│       ├── values.yaml
│       ├── install.sh
│       └── README.md
└── docs/
    ├── INFRA.md
    ├── ARCHITECTURE.md
    ├── VPN-DEPLOY.md
    ├── K8S-CLUSTER.md
    ├── VAULT.md
    └── ENABLE_K8S_VAULT.md
```

---

## Déploiement rapide

### infra_platform (cluster pour Vault, Kafka, etc.)

```bash
cd terraform/infra_platform
cp terraform.tfvars.example terraform.tfvars
# Éditer terraform.tfvars (ssh_public_key_default_user)
terraform init && terraform apply
# Vault : install_vault=true dans tfvars, ou manuellement cd ../../tools/vault && ./install.sh
```

### infra_app (cluster pour applications)

```bash
cd terraform/infra_app
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
# Déployer les apps via Helm, kubectl ou GitOps
```

### Accès via VPN (deploy_vpn = true)

Dans `terraform.tfvars` : `deploy_vpn = true`, `vpn_user_list = ["user1"]`. OpenVPN est installé **sur le master** du cluster. Les clients se connectent à l’IP du master (k8s_master_floating_ip) pour joindre le cluster via VPN.

---

## Documentation détaillée

- **Infras** — infra_platform, infra_app, deploy_vpn : [docs/INFRA.md](docs/INFRA.md)
- **Architecture** — VPN sur master, K8s : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **VPN** — déploiement, accès : [docs/VPN-DEPLOY.md](docs/VPN-DEPLOY.md)
- **Cluster K8s** — kubectl, Helm : [docs/K8S-CLUSTER.md](docs/K8S-CLUSTER.md)
- **Vault** — user/pass, SSO, Active Directory : [docs/VAULT.md](docs/VAULT.md)
- **Kubernetes Auth (Vault)** — authentifier des pods infra_app dans Vault (infra_platform) : [docs/ENABLE_K8S_VAULT.md](docs/ENABLE_K8S_VAULT.md)
- **Tools** — charts Helm : [tools/README.md](tools/README.md)

---

## Licence

BSD (voir les rôles Ansible).
