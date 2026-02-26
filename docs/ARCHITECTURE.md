# Architecture — infras, VPN sur master, cluster K8s

Architecture créée par les infras Terraform (**infra_platform**, **infra_app**) : clusters Kubernetes sur OpenStack Infomaniak, avec OpenVPN optionnel **sur le master**.

---

## 1. Vue d'ensemble

| Option | Description |
|--------|-------------|
| **deploy_k8s** | Cluster K8s (1 master + N workers, Ansible K3s) |
| **deploy_vpn** | OpenVPN installé **sur le master** (accès cluster via VPN) |

Plus de VPS séparé : le VPN tourne sur le nœud master du cluster.

---

## 2. Topologie réseau

```
                    Internet
                         │
                         ▼
              ┌──────────────────────┐
              │  Réseau externe       │  (ext-floating1)
              └──────────┬────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Cluster (deploy_k8s) │
              │  Subnet 10.0.x.0/24  │
              │  Master + Workers K3s│
              │  + OpenVPN sur master │  si deploy_vpn
              └──────────────────────┘
```

---

## 3. Composants

### Module cluster (deploy_k8s = true)

- Keypair, routeur, réseau, subnet (préfixés par `infra_name`)
- 1 master K3s + N workers
- Ansible : k8s_cluster.yml (K3s server + agents)
- Si **deploy_vpn** : Ansible openvpn_server + openvpn_client sur le master
- Security groups : SSH interne, trafic interne, master public (SSH, 6443, 1194 si deploy_vpn)

---

## 4. Section tools/

Les outils (Vault, etc.) sont installés **manuellement** ou via `install_vault=true` (infra_platform) sur un cluster existant :

```
tools/
├── README.md
└── vault/
    ├── values.yaml
    ├── install.sh
    └── README.md
```

---

## 5. Flux de travail

1. **Terraform** : `cd terraform/infra_platform` (ou infra_app) puis `terraform apply`
2. **Kubeconfig** : récupérer depuis le master
3. **Tools** : `cd tools/vault && ./install.sh`
