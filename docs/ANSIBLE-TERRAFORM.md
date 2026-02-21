# Rôle des fichiers *ansible*.tf (05 et 06)

Les stacks **01_vpn** et **02_cluster** sont **séparés** (états Terraform différents). Les numéros 05 et 06 ne sont pas dans le même répertoire : ils ne se “croisent” pas.

---

## Stack 01_vpn

| Fichier | Rôle | Ce qu’il lance |
|--------|------|-----------------|
| **05_ansible.tf** | Après création de la VM OpenVPN, lance Ansible pour installer et configurer le VPN. | 1. `openvpn_server.yml` → rôle **openvpn_server** (install + config du serveur) sur la VM.<br>2. Pour chaque user dans `vpn_user_list` : `openvpn_client.yml` → rôle **openvpn_client** (génération du `.ovpn` et fetch). |

Il n’y a **pas de 06** dans 01_vpn.

**Si tu retires 05_ansible.tf du stack 01_vpn :**

- La VM OpenVPN est toujours créée par Terraform (réseau, IP flottante, etc.).
- En revanche, **OpenVPN n’est plus installé ni configuré** sur cette VM, et **aucun fichier `.ovpn` client n’est généré**.
- Tu dois alors lancer toi-même les playbooks Ansible (avec un inventaire correct) pour avoir un serveur VPN utilisable et des clients.

---

## Stack 02_cluster

| Fichier | Rôle | Ce qu’il lance |
|--------|------|-----------------|
| **06_ansible_k3s.tf** | Après création des 3 VMs (1 master + 2 workers), lance Ansible pour installer K3s. | Un seul playbook : **k8s_cluster.yml**, qui enchaîne :<br>1. Rôle **k3s_server** sur le groupe `k8s_master` (1 nœud).<br>2. Rôle **k3s_agent** sur le groupe `k8s_worker` (2 nœuds). |

Il n’y a **pas de 05** dans 02_cluster (on a tout mis dans 06 pour le K3s).

**Si tu retires 06_ansible_k3s.tf du stack 02_cluster :**

- Les 3 VMs sont toujours créées par Terraform.
- En revanche, **K3s n’est plus installé** : pas de serveur sur le master, pas d’agents sur les workers.
- Tu dois alors lancer toi-même `k8s_cluster.yml` (avec un inventaire correct) pour avoir un cluster utilisable.

---

## 05 et 06 sont-ils incompatibles ?

**Non.** Ils ne sont pas dans le même stack :

- **05_ansible.tf** n’existe que dans **01_vpn** → il ne concerne que le VPN.
- **06_ansible_k3s.tf** n’existe que dans **02_cluster** → il ne concerne que le cluster K3s.

Tu peux avoir les deux dans le dépôt sans conflit : un `terraform apply` dans 01_vpn exécute seulement le 05 ; un `terraform apply` dans 02_cluster exécute seulement le 06.

---

## Résumé

| Stack | Fichier | Rôle | Si tu le retires |
|-------|---------|------|-------------------|
| **01_vpn** | **05_ansible.tf** | Lancer Ansible VPN (serveur + clients) après création de la VM. | VM VPN créée, mais pas d’OpenVPN installé ni de `.ovpn` générés. |
| **02_cluster** | **06_ansible_k3s.tf** | Lancer Ansible K3s (k3s_server + k3s_agent) après création des 3 VMs. | 3 VMs créées, mais pas de K3s installé. |

Les deux fichiers font la même *forme* de chose (Terraform appelle Ansible après les VMs), mais chacun dans son stack et pour son usage (VPN vs K3s).
