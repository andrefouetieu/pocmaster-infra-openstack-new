output "k8s_master_internal_ip" {
  value = try(module.k8s_master.instance_internal_ip[0], null)
}
output "k8s_master_floating_ip" {
  value = try(module.k8s_master.instance_external_ip_random[0], null)
}
output "k8s_master_name" {
  value = try(module.k8s_master.instance_compute_name[0], null)
}
output "k8s_worker_internal_ips" {
  value = try(module.k8s_worker.instance_internal_ip, [])
}
