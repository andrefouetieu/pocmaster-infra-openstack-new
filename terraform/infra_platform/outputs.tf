# Outputs cluster K8s (si deploy_k8s=true)
output "k8s_master_floating_ip" {
  description = "IP flottante du master K8s (point d'accès VPN si deploy_vpn)"
  value       = var.deploy_k8s ? module.cluster[0].k8s_master_floating_ip : null
}

output "k8s_master_internal_ip" {
  description = "IP interne du master K8s"
  value       = var.deploy_k8s ? module.cluster[0].k8s_master_internal_ip : null
}

output "k8s_master_name" {
  description = "Nom de l'instance master K8s"
  value       = var.deploy_k8s ? module.cluster[0].k8s_master_name : null
}

output "vm_ssh_user" {
  description = "User SSH"
  value       = var.vm_ssh_user
}
