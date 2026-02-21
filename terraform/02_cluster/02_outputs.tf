output "k8s_master_internal_ip" {
  description = "IP interne du nœud master (subnet cluster)"
  value       = try(module.k8s_master.instance_internal_ip[0], null)
}

output "k8s_master_floating_ip" {
  description = "IP flottante du master (si k8s_master_floating_ip = true)"
  value       = try(module.k8s_master.instance_external_ip_random[0], null)
}

output "k8s_master_name" {
  description = "Nom de l'instance master dans OpenStack"
  value       = try(module.k8s_master.instance_compute_name[0], null)
}

output "k8s_worker_internal_ips" {
  description = "IPs internes des nœuds workers"
  value       = try(module.k8s_worker.instance_internal_ip, [])
}

output "k8s_worker_names" {
  description = "Noms des instances workers dans OpenStack"
  value       = try(module.k8s_worker.instance_compute_name, [])
}
