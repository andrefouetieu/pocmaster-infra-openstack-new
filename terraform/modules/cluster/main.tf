locals {
  cluster_key_name    = "${var.name_prefix}-cluster-key"
  cluster_router_name = "${var.name_prefix}-rt"
  cluster_sg_prefix   = "${var.name_prefix}-"
}

resource "openstack_compute_keypair_v2" "cluster_key" {
  name       = local.cluster_key_name
  public_key = var.ssh_public_key_default_user
}

resource "openstack_networking_router_v2" "cluster_router" {
  name                = local.cluster_router_name
  admin_state_up      = true
  external_network_id = var.network_external_id
}

module "cluster_network" {
  source               = "../network"
  network_name         = var.cluster_network_name
  network_subnet_cidr  = var.network_subnet_cidr
  router_id           = openstack_networking_router_v2.cluster_router.id
}

resource "openstack_networking_secgroup_v2" "cluster_ssh" {
  name        = "${local.cluster_sg_prefix}cluster-ssh-internal"
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
  name        = "${local.cluster_sg_prefix}cluster-all-internal"
  description = "Trafic interne cluster"
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

resource "openstack_networking_secgroup_v2" "cluster_master_public" {
  count       = var.k8s_master_floating_ip ? 1 : 0
  name        = "${local.cluster_sg_prefix}cluster-master-public"
  description = "SSH et API K8s depuis internet"
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
resource "openstack_networking_secgroup_rule_v2" "cluster_master_openvpn" {
  count             = (var.k8s_master_floating_ip && var.deploy_vpn) ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1194
  port_range_max    = 1194
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}
resource "openstack_networking_secgroup_rule_v2" "cluster_master_openvpn_tcp" {
  count             = (var.k8s_master_floating_ip && var.deploy_vpn) ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1194
  port_range_max    = 1194
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}
resource "openstack_networking_secgroup_rule_v2" "cluster_master_vault" {
  count             = (var.k8s_master_floating_ip && var.install_vault) ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30200
  port_range_max    = 30200
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}
resource "openstack_networking_secgroup_rule_v2" "cluster_master_mongodb" {
  count             = (var.k8s_master_floating_ip && var.install_mongodb) ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30017
  port_range_max    = 30017
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.cluster_master_public[0].id
}

module "k8s_master" {
  source                         = "../instance"
  instance_count                 = 1
  instance_name                  = "${var.name_prefix}-k8s-master"
  instance_key_pair              = openstack_compute_keypair_v2.cluster_key.name
  instance_security_groups       = concat(
    [
      openstack_networking_secgroup_v2.cluster_ssh.name,
      openstack_networking_secgroup_v2.cluster_all_internal.name,
      "default"
    ],
    var.k8s_master_floating_ip ? [openstack_networking_secgroup_v2.cluster_master_public[0].name] : []
  )
  instance_network_internal      = var.cluster_network_name
  instance_ssh_key               = var.ssh_public_key_default_user
  instance_ssh_user              = var.vm_ssh_user
  instance_image_id              = var.instance_image_id
  instance_flavor_name           = var.instance_flavor_name
  public_floating_ip             = var.k8s_master_floating_ip
  instance_network_external_id   = var.k8s_master_floating_ip ? var.network_external_id : ""
  instance_network_external_name = var.k8s_master_floating_ip ? var.network_external_name : ""
  metadatas = { environment = "dev", role = "control-plane" }
  depends_on = [module.cluster_network]
}

module "k8s_worker" {
  source                   = "../instance"
  instance_count           = var.k8s_worker_count
  instance_name            = "${var.name_prefix}-k8s-worker"
  instance_key_pair        = openstack_compute_keypair_v2.cluster_key.name
  instance_security_groups = [
    openstack_networking_secgroup_v2.cluster_ssh.name,
    openstack_networking_secgroup_v2.cluster_all_internal.name,
    "default"
  ]
  instance_network_internal = var.cluster_network_name
  instance_ssh_key          = var.ssh_public_key_default_user
  instance_ssh_user         = var.vm_ssh_user
  instance_image_id        = var.instance_image_id
  instance_flavor_name     = var.instance_flavor_name
  public_floating_ip      = false
  metadatas = { environment = "dev", role = "worker" }
  depends_on = [module.cluster_network]
}

locals {
  k8s_master_ip   = coalesce(
    try(module.k8s_master.instance_external_ip_random[0], ""),
    module.k8s_master.instance_internal_ip[0]
  )
  k8s_master_name  = module.k8s_master.instance_compute_name[0]
  k8s_worker_ips   = module.k8s_worker.instance_internal_ip
  k8s_worker_names = module.k8s_worker.instance_compute_name
}

resource "null_resource" "k8s_ansible" {
  count = var.run_k8s_ansible_after_apply ? 1 : 0
  triggers = { always_run = timestamp() }
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      sleep 45
      INI=/tmp/k8s_cluster.ini
      echo "" > $INI
      echo "[k8s_master]" >> $INI
      echo "${local.k8s_master_name} ansible_host=${local.k8s_master_ip}" >> $INI
      echo "" >> $INI
      echo "[k8s_worker]" >> $INI
      %{for i, name in local.k8s_worker_names~}
      echo "${name} ansible_host=${local.k8s_worker_ips[i]}" >> $INI
      %{endfor~}
      %{if var.k8s_master_floating_ip~}
      echo "" >> $INI
      echo "[k8s_worker:vars]" >> $INI
      echo "ansible_ssh_common_args=-o 'ProxyCommand=ssh -W %h:%p -i ~/.ssh/id_rsa ${var.vm_ssh_user}@${local.k8s_master_ip}'" >> $INI
      %{endif~}
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        ${var.ansible_base_path}/k8s_cluster.yml
      rm -f $INI
    EOT
  }
  depends_on = [module.k8s_master, module.k8s_worker]
}

resource "null_resource" "vault_ansible" {
  count = var.install_vault ? 1 : 0
  triggers = { always_run = timestamp() }
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      sleep 15
      INI=/tmp/vault_install.ini
      echo "[k8s_master]" > $INI
      echo "${local.k8s_master_name} ansible_host=${local.k8s_master_ip}" >> $INI
      %{if var.k8s_master_floating_ip~}
      echo "" >> $INI
      echo "[k8s_master:vars]" >> $INI
      echo "ansible_user=${var.vm_ssh_user}" >> $INI
      %{endif~}
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        ${var.ansible_base_path}/vault_install.yml
      rm -f $INI
    EOT
  }
  depends_on = [null_resource.k8s_ansible]
}

resource "null_resource" "mongodb_ansible" {
  count = var.install_mongodb ? 1 : 0
  triggers = { always_run = timestamp() }
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      sleep 15
      INI=/tmp/mongodb_install.ini
      echo "[k8s_master]" > $INI
      echo "${local.k8s_master_name} ansible_host=${local.k8s_master_ip}" >> $INI
      %{if var.k8s_master_floating_ip~}
      echo "" >> $INI
      echo "[k8s_master:vars]" >> $INI
      echo "ansible_user=${var.vm_ssh_user}" >> $INI
      %{endif~}
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        ${var.ansible_base_path}/mongodb_install.yml
      rm -f $INI
    EOT
  }
  depends_on = [null_resource.k8s_ansible]
}

resource "null_resource" "openvpn_on_master" {
  count = var.deploy_vpn ? 1 : 0
  triggers = {
    always_run = timestamp()
    vpn_users  = join(",", var.vpn_user_list)
  }
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      sleep 30
      INI=/tmp/openvpn_master.ini
      echo "[openvpn]" > $INI
      echo "${local.k8s_master_name} ansible_host=${local.k8s_master_ip}" >> $INI
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        ${var.ansible_base_path}/openvpn_server.yml
      rm -f $INI
    EOT
  }
  depends_on = [module.k8s_master, module.k8s_worker, null_resource.k8s_ansible]
}

resource "null_resource" "openvpn_client_on_master" {
  for_each = var.deploy_vpn ? toset(var.vpn_user_list) : toset([])
  triggers = {
    name       = each.value
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      INI=/tmp/openvpn_master.ini
      echo "[openvpn]" > $INI
      echo "${local.k8s_master_name} ansible_host=${local.k8s_master_ip}" >> $INI
      ANSIBLE_CONFIG=${var.ansible_base_path}/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        -e vpn_user_list=${each.value} \
        ${var.ansible_base_path}/openvpn_client.yml
      rm -f $INI
    EOT
  }
  depends_on = [null_resource.openvpn_on_master]
}
