output "openvpn_floating_ip" {
  description = "IP flottante du serveur OpenVPN (accès SSH et connexion VPN)"
  value       = try(module.openvpn.instance_external_ip_random[0], null)
}

output "openvpn_name" {
  description = "Nom de l'instance OpenVPN dans OpenStack"
  value       = try(module.openvpn.instance_compute_name[0], null)
}
