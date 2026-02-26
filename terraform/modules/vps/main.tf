locals {
  vps_key_name     = coalesce(var.vps_key_name, "${var.name_prefix}-vps-key")
  vps_router_name  = coalesce(var.vps_router_name, "${var.name_prefix}-rt")
  vps_network_name = "${var.name_prefix}-network"
  sg_prefix        = "${var.name_prefix}-"
}

resource "openstack_compute_keypair_v2" "vps_key" {
  name       = local.vps_key_name
  public_key = var.ssh_public_key_default_user
}

resource "openstack_networking_router_v2" "vps_router" {
  name                = local.vps_router_name
  admin_state_up      = true
  external_network_id = var.network_external_id
}

module "vps_network" {
  source               = "../network"
  network_name         = local.vps_network_name
  network_subnet_cidr  = var.vps_subnet_cidr
  router_id            = openstack_networking_router_v2.vps_router.id
}

resource "openstack_networking_secgroup_v2" "vps_ssh" {
  name        = "${local.sg_prefix}vps-ssh"
  description = "SSH depuis internet"
}

resource "openstack_networking_secgroup_rule_v2" "vps_ssh_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vps_ssh.id
}

resource "openstack_networking_secgroup_v2" "vps_openvpn" {
  name        = "${local.sg_prefix}vps-openvpn"
  description = "OpenVPN (UDP/TCP 1194)"
}

resource "openstack_networking_secgroup_rule_v2" "vps_openvpn_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1194
  port_range_max    = 1194
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vps_openvpn.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_openvpn_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1194
  port_range_max    = 1194
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.vps_openvpn.id
}

resource "openstack_networking_secgroup_v2" "vps_ssh_internal" {
  name        = "${local.sg_prefix}vps-ssh-internal"
  description = "SSH depuis le subnet VPS"
}

resource "openstack_networking_secgroup_rule_v2" "vps_ssh_internal_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_ssh_internal.id
}

resource "openstack_networking_secgroup_v2" "vps_all_internal" {
  name        = "${local.sg_prefix}vps-all-internal"
  description = "Trafic interne subnet VPS"
}

resource "openstack_networking_secgroup_rule_v2" "vps_all_internal_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_all_internal.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_all_internal_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_all_internal.id
}

resource "openstack_networking_secgroup_v2" "vps_proxy" {
  name        = "${local.sg_prefix}vps-proxy"
  description = "HTTP/HTTPS depuis le subnet VPS"
}

resource "openstack_networking_secgroup_rule_v2" "vps_proxy_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_proxy.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_proxy_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_proxy.id
}

resource "openstack_networking_secgroup_v2" "vps_consul" {
  name        = "${local.sg_prefix}vps-consul"
  description = "Consul (DNS, HTTP, gRPC, WAN)"
}

resource "openstack_networking_secgroup_rule_v2" "vps_consul_dns_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8600
  port_range_max    = 8600
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_consul.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_consul_dns_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 8600
  port_range_max    = 8600
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_consul.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_consul_http_grpc" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8500
  port_range_max    = 8503
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_consul.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_consul_wan_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8300
  port_range_max    = 8302
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_consul.id
}

resource "openstack_networking_secgroup_rule_v2" "vps_consul_wan_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 8300
  port_range_max    = 8302
  remote_ip_prefix  = var.vps_subnet_cidr
  security_group_id = openstack_networking_secgroup_v2.vps_consul.id
}

module "openvpn" {
  source                        = "../instance"
  instance_count                = 1
  instance_name                 = "openvpn"
  instance_key_pair             = openstack_compute_keypair_v2.vps_key.name
  instance_security_groups      = [
    openstack_networking_secgroup_v2.vps_openvpn.name,
    openstack_networking_secgroup_v2.vps_ssh.name,
    "default"
  ]
  instance_network_internal     = local.vps_network_name
  instance_network_external_name = var.vps_floating_ip ? var.network_external_name : ""
  instance_network_external_id   = var.vps_floating_ip ? var.network_external_id : ""
  instance_ssh_key              = var.ssh_public_key_default_user
  instance_ssh_user             = var.vm_ssh_user
  instance_image_id             = var.instance_image_id
  instance_flavor_name          = var.instance_flavor_name
  public_floating_ip            = var.vps_floating_ip
  metadatas                    = var.metadatas
  depends_on                    = [module.vps_network, openstack_networking_secgroup_rule_v2.vps_openvpn_tcp]
}

locals {
  vps_ip   = coalesce(
    try(module.openvpn.instance_external_ip_random[0], ""),
    module.openvpn.instance_internal_ip[0]
  )
  vps_name = module.openvpn.instance_compute_name[0]
}

resource "null_resource" "openvpn_server" {
  count = var.run_vps_ansible_after_apply ? 1 : 0

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      sleep 20
      INI=/tmp/openvpn.ini
      echo "" > $INI
      echo "[openvpn]" >> $INI
      echo "${local.vps_name} ansible_host=${local.vps_ip}" >> $INI
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        ${var.ansible_base_path}/openvpn_server.yml
      rm -f $INI
    EOT
  }
  depends_on = [module.openvpn, module.vps_network]
}

resource "null_resource" "create_new_vpn_client" {
  for_each = var.run_vps_ansible_after_apply ? toset(var.vpn_user_list) : toset([])

  triggers = {
    name       = each.value
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      INI=/tmp/openvpn.ini
      echo "" > $INI
      echo "[openvpn]" >> $INI
      echo "${local.vps_name} ansible_host=${local.vps_ip}" >> $INI
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        -e vpn_user_list=${each.value} \
        ${var.ansible_base_path}/openvpn_client.yml
      rm -f $INI
    EOT
  }
  depends_on = [module.openvpn, module.vps_network, null_resource.openvpn_server]
}
