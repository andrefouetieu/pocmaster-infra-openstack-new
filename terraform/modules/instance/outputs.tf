output "instance_internal_ip" {
  description = "Internal"
  value       = try(openstack_compute_instance_v2.instance[*].network[0].fixed_ip_v4,null)
}

output "instance_external_ip_random" {
  description = "Public"
  value       = try(openstack_networking_floatingip_v2.floatip_1_random[*].address,null)
}

output "instance_external_ip_fixed" {
  description = "Public"
  value       = try(var.public_floating_ip_fixed,null)
}

output "instance_compute_name" {
  description = "Internal"
  value       = try(openstack_compute_instance_v2.instance[*].name,null)
}