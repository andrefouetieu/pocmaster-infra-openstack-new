variable "name_prefix" {
  type        = string
  default     = "vps"
  description = "Préfixe pour les noms des ressources OpenStack (évite les conflits)"
}

variable "network_external_id" {
  type    = string
  default = "0f9c3806-bd21-490f-918d-4a6d1c648489"
}
variable "network_external_name" {
  type    = string
  default = "ext-floating1"
}

variable "vps_network_name" {
  type        = string
  default     = "vps_network"
  description = "Nom du réseau OpenStack"
}
variable "vps_subnet_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "CIDR du subnet VPS"
}
variable "vps_key_name" {
  type        = string
  default     = null
  description = "Nom de la keypair OpenStack (défaut: {name_prefix}-vps-key)"
}
variable "vps_router_name" {
  type        = string
  default     = null
  description = "Nom du routeur OpenStack (défaut: {name_prefix}-rt)"
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
variable "metadatas" {
  type = map(string)
  default = {
    "environment" = "dev"
  }
}

variable "vps_floating_ip" {
  type        = bool
  default     = true
  description = "Attribuer une IP flottante à la VM"
}
variable "run_vps_ansible_after_apply" {
  type        = bool
  default     = true
  description = "Lancer Ansible (openvpn_server + openvpn_client) après apply"
}
variable "vpn_user_list" {
  type        = list(string)
  default     = []
  description = "Liste des utilisateurs VPN pour les certificats .ovpn"
}

variable "ansible_base_path" {
  type        = string
  description = "Chemin vers le répertoire ansible (ex. ../../ansible ou path.root/../../ansible)"
}
