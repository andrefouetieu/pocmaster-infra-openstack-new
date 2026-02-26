variable "name_prefix" {
  type        = string
  default     = "cluster"
  description = "Préfixe pour les noms des ressources (évite conflits multi-infra)"
}
variable "cluster_network_name" {
  type        = string
  description = "Nom du réseau OpenStack du cluster"
}
variable "k8s_worker_count" {
  type        = number
  default     = 2
  description = "Nombre de nœuds workers"
}
variable "network_subnet_cidr" {
  type        = string
  description = "CIDR du subnet cluster"
}
variable "network_external_id" {
  type = string
}
variable "network_external_name" {
  type = string
}
variable "ssh_public_key_default_user" {
  type      = string
  sensitive = true
}
variable "vm_ssh_user" {
  type    = string
  default = "ubuntu"
}
variable "instance_image_id" {
  type    = string
  default = "cdf81c97-4873-473b-b0a3-f407ce837255"
}
variable "instance_flavor_name" {
  type    = string
  default = "a1-ram2-disk20-perf1"
}
variable "k8s_master_floating_ip" {
  type    = bool
  default = false
}
variable "run_k8s_ansible_after_apply" {
  type    = bool
  default = true
}
variable "deploy_vpn" {
  type        = bool
  default     = false
  description = "Installer OpenVPN sur le master (accès cluster via VPN)"
}
variable "vpn_user_list" {
  type        = list(string)
  default     = []
  description = "Utilisateurs pour les certificats .ovpn (si deploy_vpn)"
}
variable "ansible_base_path" {
  type = string
}
