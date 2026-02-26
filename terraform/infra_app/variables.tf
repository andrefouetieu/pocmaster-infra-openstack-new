variable "openstack_cloud" {
  type        = string
  default     = ""
  description = "Nom du cloud dans clouds.yaml"
}
variable "openstack_auth_url" {
  type    = string
  default = ""
}
variable "openstack_username" {
  type    = string
  default = ""
}
variable "openstack_password" {
  type      = string
  default   = ""
  sensitive = true
}
variable "openstack_project_name" {
  type    = string
  default = ""
}
variable "openstack_region_name" {
  type    = string
  default = ""
}
variable "openstack_user_domain_name" {
  type    = string
  default = "default"
}
variable "openstack_project_domain_name" {
  type    = string
  default = "default"
}

variable "infra_name" {
  type    = string
  default = "app"
}

variable "network_external_id" {
  type    = string
  default = "0f9c3806-bd21-490f-918d-4a6d1c648489"
}
variable "network_external_name" {
  type    = string
  default = "ext-floating1"
}

variable "deploy_vpn" {
  type        = bool
  default     = false
  description = "Créer un VPS avec OpenVPN (remplace 01_vps)"
}
variable "deploy_k8s" {
  type        = bool
  default     = true
  description = "Créer un cluster K8s (1 master + N workers)"
}

variable "cluster_subnet_cidr" {
  type        = string
  default     = "10.0.20.0/24"
  description = "CIDR du subnet du cluster K8s (dédié applications)"
}

variable "ssh_public_key_default_user" {
  type        = string
  sensitive   = true
  description = "Clé SSH publique"
}
variable "vm_ssh_user" {
  type        = string
  default     = "ubuntu"
  description = "User SSH sur les VMs"
}
variable "instance_image_id" {
  type    = string
  default = "cdf81c97-4873-473b-b0a3-f407ce837255"
}
variable "instance_flavor_name" {
  type    = string
  default = "a1-ram2-disk20-perf1"
}

variable "vpn_user_list" {
  type        = list(string)
  default     = []
  description = "Utilisateurs VPN pour les certificats .ovpn (si deploy_vpn)"
}

variable "k8s_worker_count" {
  type        = number
  default     = 2
  description = "Nombre de workers du cluster K8s"
}
variable "k8s_master_floating_ip" {
  type        = bool
  default     = true
  description = "IP flottante sur le master K8s (accès SSH et kubectl)"
}
variable "run_k8s_ansible_after_apply" {
  type        = bool
  default     = true
  description = "Lancer Ansible (K3s) après apply (si deploy_k8s)"
}
