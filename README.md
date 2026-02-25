# infra-openstack

Déploiement sur le cloud Infomaniak (OpenStack) avec **Terraform** et **Ansible** :

- **01_vpn** : serveur **OpenVPN** (réseau, VM, génération des clients `.ovpn`).
- **02_infrastructure** : cluster **Kubernetes (K3s)** — 1 master + 2 workers, sur le même réseau que le VPN. Accès au cluster via le VPN pour déployer des projets K8s.

---

## Prérequis

- **Terraform** >= 0.14
- **Ansible**
- Compte **Infomaniak** (OpenStack) et credentials configurés (variables d’environnement ou `clouds.yaml`)
- Clé SSH (publique fournie à Terraform, privée pour se connecter à la VM)

Installation des collections Ansible (pour le rôle openvpn_server) :

```bash
cd ansible && ansible-galaxy collection install -r requirements.yml
```

---

## Structure du dépôt

```
.
├── ansible/                    # Playbooks et rôles Ansible
│   ├── openvpn_server.yml      # Configure le serveur VPN sur la VM
│   ├── openvpn_client.yml      # Génère les configs client (.ovpn) et les récupère
│   ├── k8s_cluster.yml         # Installe K3s (master + workers)
│   ├── k8s_kubectl_config.yml  # Configure kubectl sur le master (optionnel)
│   ├── k8s_helm.yml            # Installe Helm sur le master (optionnel)
│   ├── ansible.cfg
│   ├── envs/dev/               # Inventaire et variables (dev)
│   └── roles/
│       ├── openvpn_server/     # Serveur OpenVPN
│       ├── openvpn_client/     # Clients OpenVPN (.ovpn)
│       ├── k3s_server/          # K3s master (control-plane)
│       ├── k3s_agent/           # K3s workers
│       ├── kubectl_config/      # Config kubectl (~/.kube/config sur le master)
│       └── helm/                # Installation Helm
├── terraform/
│   ├── 01_vpn/                 # Stack VPN : réseau, VM OpenVPN, security groups
│   ├── 02_infrastructure/     # Stack K8s : 1 master + 2 workers (indépendant de 01, peut être renommé en 02_clusters)
│   └── modules/
│       ├── instance/           # VM OpenStack (cloud-init, floating IP, etc.)
│       └── network/            # Réseau + subnet + routeur
└── docs/
    ├── VPN-DEPLOY.md          # VPN : variables, déploiement, accès SSH
    └── K8S-CLUSTER.md         # Cluster K8s : Terraform, Ansible, kubectl via VPN
```

---

## Déploiement rapide (VPN)

1. **Variables** (obligatoire : ne pas committer de clés)  
   - Copier `terraform/01_vpn/terraform.tfvars.example` en `terraform/01_vpn/terraform.tfvars`  
   - Renseigner au minimum `ssh_public_key_default_user` (ta clé publique SSH).

2. **Lancer Terraform** (depuis la racine du dépôt ou depuis `terraform/01_vpn`) :

   ```bash
   cd terraform/01_vpn
   terraform init
   terraform plan
   terraform apply
   ```

   Terraform crée le réseau, la VM OpenVPN avec une IP flottante, puis lance Ansible (serveur puis un client par utilisateur dans `vpn_user_list`). Les fichiers `.ovpn` sont récupérés sur la machine qui exécute Terraform (par défaut dans `/tmp/`).

3. **Connexion SSH au serveur**  
   User : `xavki` (défini dans le module instance).  
   Récupérer l’IP flottante :

   ```bash
   cd terraform/01_vpn
   ssh -i ~/.ssh/id_rsa xavki@$(terraform output -raw openvpn_floating_ip)
   ```

   (Adapter le chemin de la clé si besoin.)

---

## OpenVPN : serveur vs client (dans ce dépôt)

| | **OpenVPN Server** | **OpenVPN Client** |
|---|-------------------|---------------------|
| **Rôle** | Service qui tourne sur la **VM** (cloud). Écoute sur le port 1194 (UDP). | Pas un service : le rôle Ansible **génère** les configs client (certificats + `.ovpn`) et les **récupère** sur ta machine. |
| **Ansible** | Installe OpenVPN + easy-rsa, crée la CA, le certificat serveur, la config, iptables, démarre le service. | Pour chaque utilisateur : génère un certificat client, construit un fichier `.ovpn` tout-en-un, puis le **fetch** vers ton poste. |
| **Utilisation** | Une fois déployé, les clients se connectent à ce serveur avec leur `.ovpn`. | Importer le `.ovpn` dans un client OpenVPN (Tunnelblick, OpenVPN GUI, etc.) pour se connecter au serveur. |

---

## Cluster Kubernetes (stack 02 indépendant)

Le stack **02** (dossier `02_infrastructure`, que tu peux renommer en **02_clusters**) peut être déployé **sans 01_vpn** : il crée son propre réseau (10.0.2.0/24), keypair et security groups.

1. `cd terraform/02_infrastructure` (ou `02_clusters`), remplir `terraform.tfvars` (ex. `ssh_public_key_default_user`).
2. `terraform init && terraform apply` → 3 VMs (1 master, 2 workers).
3. Optionnel : `k8s_master_floating_ip = true` pour accéder au master depuis internet (SSH + kubectl) sans VPN.
4. Ansible : inventaire avec les IPs → `k8s_cluster.yml` pour installer K3s.
5. **Configuration kubectl et Helm (optionnel)** : après le cluster, tu peux lancer :
   - `ansible-playbook -i <inventaire> k8s_kubectl_config.yml` pour configurer kubectl sur le master (utilisation sans `sudo` en SSH).
   - `ansible-playbook -i <inventaire> k8s_helm.yml` pour installer Helm sur le master (charts).
   Même `-u` et `--private-key` que pour `k8s_cluster.yml` (ex. `-u xavki --private-key ~/.ssh/id_rsa`).

Voir [docs/K8S-CLUSTER.md](docs/K8S-CLUSTER.md) pour le détail.

---

## Documentation détaillée

- **VPN** — variables sensibles, déploiement, accès SSH : [docs/VPN-DEPLOY.md](docs/VPN-DEPLOY.md).
- **Cluster K8s** — Terraform, Ansible, accès kubectl via VPN : [docs/K8S-CLUSTER.md](docs/K8S-CLUSTER.md).

---

## Licence

BSD (voir les rôles Ansible).
