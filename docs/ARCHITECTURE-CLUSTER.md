# Architecture – Infrastructure cluster Kubernetes (stack 02)

Ce document décrit l’infrastructure créée par le stack Terraform **02_cluster** : un cluster Kubernetes (K3s) sur OpenStack Infomaniak, avec un nœud master et deux workers.

---

## 1. Vue d’ensemble

Le stack **02_cluster** est **indépendant** du stack 01_vpn. Il crée :

| Composant | Description |
|-----------|--------------|
| **Réseau** | Un réseau privé dédié au cluster, un subnet, un routeur connecté au réseau externe (NAT sortant). |
| **Sécurité** | Une keypair SSH, trois security groups (SSH interne, trafic interne cluster, optionnel : master public). |
| **Compute** | 1 VM **master** (control-plane) + 2 VMs **workers**, sur le même subnet. |
| **Post-déploiement** | Ansible installe K3s (rôles `k3s_server` sur le master, `k3s_agent` sur les workers). |

**Région** : une seule région OpenStack par déploiement (ex. `dc3-a` ou `dc4-a`), configurée via `openstack_region_name` ou `openstack_cloud` dans `terraform.tfvars`.

---

## 2. Réseau

### 2.1 Topologie

```
                    Internet
                         │
                         ▼
              ┌──────────────────────┐
              │  Réseau externe      │  (ext-floating1, fourni par Infomaniak)
              │  network_external_id │
              └──────────┬───────────┘
                         │
                         │ routeur (NAT, passerelle par défaut)
                         ▼
              ┌──────────────────────┐
              │  Router cluster      │  rt-cluster
              └──────────┬───────────┘
                         │
                         │ interface sur subnet cluster
                         ▼
              ┌──────────────────────┐
              │  Réseau cluster     │  cluster_network (var.cluster_network_name)
              │  Subnet              │  CIDR par défaut : 10.0.2.0/24
              └──────────┬───────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
    k8s-master1    k8s-worker1    k8s-worker2
    (IP fixe       (IP fixe       (IP fixe
     subnet)        subnet)        subnet)
```

### 2.2 Ressources créées

| Ressource Terraform | Nom / paramètre | Rôle |
|---------------------|-----------------|------|
| `openstack_networking_router_v2.cluster_router` | `rt-cluster` | Routeur avec interface vers le réseau externe (NAT sortant). |
| Module `cluster_network` | Réseau : `cluster_network` (défaut) | Réseau privé du cluster. |
| (module) | Subnet : même nom, CIDR `network_subnet_cidr` (défaut `10.0.2.0/24`) | Subnet où sont attachées les VMs. |
| (module) | Router interface | Attache le subnet au routeur pour accès internet (egress). |

Les VMs n’ont **pas** d’IP flottante par défaut (sauf option sur le master). L’accès se fait via les **IP du subnet** (10.0.2.x), donc depuis un réseau qui peut joindre ce subnet (ex. VPN 01_vpn en 10.0.1.0/24 si routage, ou jump host sur le même projet OpenStack).

---

## 3. Sécurité

### 3.1 Keypair

| Ressource | Nom | Usage |
|-----------|-----|--------|
| `openstack_compute_keypair_v2.cluster_key` | `cluster_key` | Clé publique fournie par `ssh_public_key_default_user` ; utilisée pour toutes les VMs du cluster (master + workers). |

### 3.2 Security groups

| Groupe | Nom | Règles | Appliqué à |
|--------|-----|--------|------------|
| **cluster-ssh-internal** | `cluster-ssh-internal` | TCP 22 (SSH) depuis `network_subnet_cidr` (ex. 10.0.2.0/24) | Master + workers |
| **cluster-all-internal** | `cluster-all-internal` | TCP 1–65535 et UDP 1–65535 depuis `network_subnet_cidr` | Master + workers (trafic K8s, K3s, etc.) |
| **cluster-master-public** | `cluster-master-public` | TCP 22 (SSH) et TCP 6443 (API K8s) depuis 0.0.0.0/0 | Master **uniquement** si `k8s_master_floating_ip = true` |

En plus, le groupe **default** OpenStack est attaché à chaque VM.

Résumé des flux :

- **SSH** : autorisé depuis le subnet du cluster ; si le master a une IP flottante, SSH autorisé depuis internet.
- **API Kubernetes (6443)** : ouverte depuis internet **uniquement** si le master a une IP flottante ; sinon uniquement depuis le subnet.
- **Trafic interne** : tout TCP/UDP entre nœuds du cluster (même subnet) est autorisé.

---

## 4. Compute (VMs)

### 4.1 Nœud master

| Attribut | Valeur / source |
|----------|------------------|
| Nom | `k8s-master1` (une seule instance) |
| Rôle | Control-plane K3s |
| Réseau | `cluster_network` (subnet 10.0.2.0/24) |
| Image | `instance_image_id` (ex. ID Infomaniak Ubuntu) |
| Flavor | `instance_flavor_name` (ex. `a1-ram2-disk20-perf1`) |
| Security groups | cluster-ssh-internal, cluster-all-internal, default ; + cluster-master-public si `k8s_master_floating_ip = true` |
| IP flottante | Optionnelle : `k8s_master_floating_ip` (défaut `false`) ; si `true`, une IP du pool `network_external_name` est associée au master. |
| Métadonnées | `environment = dev`, `role = control-plane` |

### 4.2 Nœuds workers

| Attribut | Valeur / source |
|----------|------------------|
| Noms | `k8s-worker1`, `k8s-worker2` |
| Rôle | Workers K3s |
| Réseau | `cluster_network` (même subnet que le master) |
| Image / Flavor | Identiques au master |
| Security groups | cluster-ssh-internal, cluster-all-internal, default (pas d’IP flottante, pas de groupe public) |
| Métadonnées | `environment = dev`, `role = worker` |

### 4.3 User data

Chaque VM reçoit un **user_data** (template dans `modules/instance/templates/userdata.yaml.tpl`) qui injecte la clé SSH pour l’utilisateur par défaut (ex. cloud-init), afin qu’Ansible puisse se connecter en SSH après création.

---

## 5. Post-déploiement : Ansible K3s

Après la création des VMs, si `run_k8s_ansible_after_apply = true` (défaut) :

1. Terraform attend 45 secondes (démarrage des VMs).
2. Un inventaire Ansible temporaire est généré (master + workers avec leurs IP).
3. Le playbook **ansible/k8s_cluster.yml** est exécuté :
   - **k8s_master** : rôle `k3s_server` (installation du serveur K3s).
   - **k8s_worker** : rôle `k3s_agent` (enregistrement sur le master via token et URL du master).

La machine qui lance `terraform apply` doit pouvoir joindre les IP du cluster (subnet 10.0.2.0/24 ou IP flottante du master si activée). Connexion Ansible : utilisateur et clé configurés dans le `local-exec` (ex. `-u xavki --private-key ~/.ssh/id_rsa`).

---

## 6. Options principales (variables)

| Variable | Défaut | Description |
|----------|--------|-------------|
| `cluster_network_name` | `cluster_network` | Nom du réseau (et du subnet) OpenStack. |
| `network_subnet_cidr` | `10.0.2.0/24` | CIDR du subnet du cluster. |
| `k8s_master_floating_ip` | `false` | Si `true`, le master reçoit une IP flottante (SSH et API 6443 ouverts depuis internet). |
| `run_k8s_ansible_after_apply` | `true` | Si `true`, lance le playbook K3s après création des VMs. |

Les autres variables (image, flavor, clé SSH, auth OpenStack, etc.) sont décrites dans `terraform/02_cluster/00_variables.tf` et `terraform.tfvars.example`.

---

## 7. Sorties Terraform (outputs)

| Output | Description |
|--------|-------------|
| `k8s_master_internal_ip` | IP interne du master (subnet cluster). |
| `k8s_master_floating_ip` | IP flottante du master (si activée). |
| `k8s_master_name` | Nom de l’instance master dans OpenStack. |
| `k8s_worker_internal_ips` | Liste des IP internes des workers. |
| `k8s_worker_names` | Noms des instances workers dans OpenStack. |

Utilisation typique : configurer `kubectl` vers `https://<k8s_master_internal_ip ou floating>:6443` et récupérer le kubeconfig depuis le master (voir doc K3s / `docs/K8S-SSH-ACCESS.md` si présente).

---

## 8. Résumé schématique des composants

```
Stack 02_cluster (Terraform)
│
├── Réseau
│   ├── Router (rt-cluster) → externe
│   └── Network + Subnet (10.0.2.0/24)
│
├── Sécurité
│   ├── Keypair (cluster_key)
│   ├── cluster-ssh-internal (SSH depuis subnet)
│   ├── cluster-all-internal (TCP/UDP interne)
│   └── cluster-master-public (optionnel, si floating IP master)
│
├── Compute
│   ├── k8s-master1  [optionnel : IP flottante]
│   ├── k8s-worker1
│   └── k8s-worker2
│
└── Provisioning
    └── Ansible (k8s_cluster.yml) → K3s server + agents
```

Ce document reflète l’état du stack **02_cluster** tel que décrit dans le dépôt (réseau, sécurité, instances, Ansible K3s). Pour l’auth OpenStack et l’accès SSH/kubectl, voir `docs/OPENSTACK-AUTH.md` et `docs/K8S-SSH-ACCESS.md` si disponibles.
