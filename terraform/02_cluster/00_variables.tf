# --- Authentification OpenStack (à mettre dans terraform.tfvars, ne pas committer) ---
# Option 1 : utiliser clouds.yaml (recommandé si tu as le fichier téléchargé)
#   openstack_cloud = "PCP-EJ4W6KP-dc3-a"   (ou PCP-EJ4W6KP-dc4-a pour l'autre région)
#   Le chemin du fichier clouds.yaml se définit en dehors de Terraform :
#   export OS_CLOUD_CONFIG=~/.config/Infomaniak/clouds.yaml
#   Ou place le fichier dans ~/.config/openstack/clouds.yaml (pas besoin d'export).
# Option 2 : laisser openstack_cloud vide et remplir openstack_auth_url, openstack_username, etc.
variable "openstack_cloud" {
  type        = string
  default     = "tontine-dc3-a"
  description = "Nom du cloud dans clouds.yaml (ex. PCP-EJ4W6KP-dc3-a). Si rempli, auth via clouds.yaml ; sinon via les variables openstack_*."
}
variable "openstack_auth_url" {
  type        = string
  default     = ""
  description = "URL Identity (Keystone), ex. https://api.infomaniak.com/identity/v3"
}
variable "openstack_username" {
  type        = string
  default     = ""
  description = "Utilisateur OpenStack"
}
variable "openstack_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Mot de passe OpenStack"
}
variable "openstack_project_name" {
  type        = string
  default     = ""
  description = "Nom du projet (tenant) OpenStack"
}
variable "openstack_region_name" {
  type        = string
  default     = ""
  description = "Région OpenStack, ex. dc3"
}
variable "openstack_user_domain_name" {
  type        = string
  default     = "default"
  description = "Domaine utilisateur (souvent default, comme dans clouds.yaml)"
}
variable "openstack_project_domain_name" {
  type        = string
  default     = "default"
  description = "Domaine du projet (souvent default, comme dans clouds.yaml)"
}

# ---
variable "network_external_id" {
  type    = string
  default = "0f9c3806-bd21-490f-918d-4a6d1c648489"
}

variable "network_external_name" {
  type    = string
  default = "ext-floating1"
}

# Réseau du cluster (stack 02 indépendant — pas besoin de 01_vpn)
variable "cluster_network_name" {
  type        = string
  default     = "cluster_network"
  description = "Nom du réseau OpenStack créé par ce stack"
}

variable "network_subnet_cidr" {
  type        = string
  default     = "10.0.2.0/24"
  description = "CIDR du subnet du cluster (différent de 01_vpn pour éviter chevauchement si les deux stacks coexistent)"
}

variable "ssh_public_key_default_user" {
  type    = string
  default = ""
}

# Utilisateur Linux créé sur les VMs par cloud-init (avec ta clé SSH). Ansible se connecte avec -u <cette valeur>.
# Mets ton login (ex. ton nom d'utilisateur Unix) pour que la VM et Ansible utilisent le même user.
variable "vm_ssh_user" {
  type        = string
  default     = "ubuntu"
  description = "User SSH sur les VMs (créé par userdata) ; même valeur que -u dans le playbook Ansible"
}

variable "instance_image_id" {
  type    = string
  default = "cdf81c97-4873-473b-b0a3-f407ce837255"
}

variable "instance_flavor_name" {
  type    = string
  default = "a1-ram2-disk20-perf1"
}

variable "instance_security_groups" {
  type    = list(any)
  default = ["default"]
}

variable "metadatas" {
  type = map(string)
  default = {
    "environment" = "dev"
  }
}

# Optionnel : IP flottante sur le master pour accéder au cluster sans VPN
variable "k8s_master_floating_ip" {
  type        = bool
  default     = false
  description = "Attribuer une IP flottante au master pour accès SSH/kubectl depuis internet (sans VPN)"
}

# Lancer le playbook Ansible k8s_cluster.yml après création des VMs (comme 01_vpn avec 05_ansible.tf)
variable "run_k8s_ansible_after_apply" {
  type        = bool
  default     = true
  description = "Si true, terraform apply lance Ansible pour installer K3s. La machine qui exécute Terraform doit pouvoir joindre les IP du cluster (subnet 10.0.2.0/24 ou IP flottante du master)."
}
