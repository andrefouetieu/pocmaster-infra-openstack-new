output "vps_floating_ip" {
  description = "IP flottante du VPS"
  value       = try(module.openvpn.instance_external_ip_random[0], null)
}

output "vps_internal_ip" {
  description = "IP interne du VPS"
  value       = try(module.openvpn.instance_internal_ip[0], null)
}

output "vps_name" {
  description = "Nom de l'instance VPS"
  value       = try(module.openvpn.instance_compute_name[0], null)
}

output "vm_ssh_user" {
  description = "User SSH"
  value       = var.vm_ssh_user
}
