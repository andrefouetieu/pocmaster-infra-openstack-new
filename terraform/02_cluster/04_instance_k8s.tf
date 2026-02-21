# Cluster Kubernetes : 1 master + 2 workers.
# Stack 02 indépendant : réseau, keypair et security groups sont créés dans ce stack.
# Accès aux nœuds : SSH directement sur les IP du subnet (10.0.2.0/24 par défaut).
# Si tu utilises aussi 01_vpn : connecte-toi au VPN puis accède aux IP du cluster.

module "k8s_master" {
  source                           = "../modules/instance"
  instance_count                   = 1
  instance_name                    = "k8s-master"
  instance_key_pair                = openstack_compute_keypair_v2.cluster_key.name
  instance_security_groups         = concat(
    [
      openstack_networking_secgroup_v2.cluster_ssh.name,
      openstack_networking_secgroup_v2.cluster_all_internal.name,
      "default"
    ],
    var.k8s_master_floating_ip ? [openstack_networking_secgroup_v2.cluster_master_public[0].name] : []
  )
  instance_network_internal        = var.cluster_network_name
  instance_ssh_key                 = var.ssh_public_key_default_user
  instance_ssh_user                = var.vm_ssh_user
  instance_image_id                = var.instance_image_id
  instance_flavor_name             = var.instance_flavor_name
  public_floating_ip               = var.k8s_master_floating_ip
  instance_network_external_id     = var.k8s_master_floating_ip ? var.network_external_id : ""
  instance_network_external_name   = var.k8s_master_floating_ip ? var.network_external_name : ""
  metadatas = {
    environment = "dev"
    role        = "control-plane"
  }
  depends_on = [module.cluster_network]
}

module "k8s_worker" {
  source                   = "../modules/instance"
  instance_count           = 2
  instance_name            = "k8s-worker"
  instance_key_pair        = openstack_compute_keypair_v2.cluster_key.name
  instance_security_groups = [
    openstack_networking_secgroup_v2.cluster_ssh.name,
    openstack_networking_secgroup_v2.cluster_all_internal.name,
    "default"
  ]
  instance_network_internal = var.cluster_network_name
  instance_ssh_key          = var.ssh_public_key_default_user
  instance_ssh_user         = var.vm_ssh_user
  instance_image_id         = var.instance_image_id
  instance_flavor_name      = var.instance_flavor_name
  public_floating_ip        = false
  metadatas = {
    environment = "dev"
    role        = "worker"
  }
  depends_on = [module.cluster_network]
}
