variable "network_external_id" {
  type    = string
  default = "0f9c3806-bd21-490f-918d-4a6d1c648489"
}

variable "network_external_name" {
  type    = string
  default = "ext-floating1"
}

variable "network_internal_dev" {
  type    = string
  default = "internal_dev"
}

variable "network_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

# Fournir via terraform.tfvars (fichier non versionné) ou TF_VAR_ssh_public_key_default_user
variable "ssh_public_key_default_user" {
  type        = string
  sensitive   = true
  description = "Clé SSH publique pour l'accès aux VMs (cloud-init + keypair). À définir dans terraform.tfvars ou export TF_VAR_ssh_public_key_default_user."
  validation {
    condition     = length(var.ssh_public_key_default_user) > 0
    error_message = "ssh_public_key_default_user doit être défini (terraform.tfvars ou TF_VAR_ssh_public_key_default_user)."
  }
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

variable "vpn_user_list" {
  type    = list(any)
  default = ["xpestel"]
}



