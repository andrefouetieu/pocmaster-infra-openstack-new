# Réseau dédié au cluster (stack 02 indépendant de 01_vpn).
resource "openstack_networking_router_v2" "cluster_router" {
  name                = "rt-cluster"
  admin_state_up      = true
  external_network_id = var.network_external_id
}

module "cluster_network" {
  source               = "../modules/network"
  network_name         = var.cluster_network_name
  network_subnet_cidr  = var.network_subnet_cidr
  router_id            = openstack_networking_router_v2.cluster_router.id
}
