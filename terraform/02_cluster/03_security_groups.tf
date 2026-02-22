# Security groups pour le cluster K8s (stack 02 indépendant).
resource "openstack_networking_secgroup_v2" "cluster_ssh" {
  name        = "cluster-ssh-internal"
  description = "SSH depuis le subnet du cluster"
}

resource "openstack_networking_secgroup_rule_v2" "cluster_ssh_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.network_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.cluster_ssh.id
}

resource "openstack_networking_secgroup_v2" "cluster_all_internal" {
  name        = "cluster-all-internal"
  description = "Trafic interne cluster (K8s, etc.)"
}

resource "openstack_networking_secgroup_rule_v2" "cluster_all_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = var.network_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.cluster_all_internal.id
}

resource "openstack_networking_secgroup_rule_v2" "cluster_all_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = var.network_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.cluster_all_internal.id
}

# Optionnel : utilisé quand k8s_master_floating_ip = true (accès SSH + API depuis internet)
resource "openstack_networking_secgroup_v2" "cluster_master_public" {
  count       = var.k8s_master_floating_ip ? 1 : 0
  name        = "cluster-master-public"
  description = "SSH et API K8s (6443) depuis internet pour le master"
}

resource "openstack_networking_secgroup_rule_v2" "cluster_master_ssh" {
  count             = var.k8s_master_floating_ip ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}

resource "openstack_networking_secgroup_rule_v2" "cluster_master_k8s_api" {
  count             = var.k8s_master_floating_ip ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}

resource "openstack_networking_secgroup_rule_v2" "cluster_master_http_apps" {
  count             = var.k8s_master_floating_ip ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 9100
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}

resource "openstack_networking_secgroup_rule_v2" "cluster_master_nodeport" {
  count             = var.k8s_master_floating_ip ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}
