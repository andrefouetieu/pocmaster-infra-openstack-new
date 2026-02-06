output "network_id" {
  description = "ID of the network"
  value       = openstack_networking_network_v2.network_name.id
}
