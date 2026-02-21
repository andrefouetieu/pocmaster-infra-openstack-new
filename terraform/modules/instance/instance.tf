data "openstack_networking_subnet_ids_v2" "ext_subnets" {
  count     = var.public_floating_ip ? 1 : 0
  network_id = var.instance_network_external_id
}

resource "openstack_compute_instance_v2" "instance" {
  count           = var.instance_count
  name            = "${var.instance_name}${count.index + 1}"
  image_id        = var.instance_image_id
  flavor_name     = var.instance_flavor_name
  metadata        = var.metadatas
  user_data       = templatefile("${path.module}/templates/userdata.yaml.tpl", { instance_ssh_key = var.instance_ssh_key, instance_ssh_user = var.instance_ssh_user })
  security_groups = var.instance_security_groups
  key_pair        = var.instance_key_pair

  network {
    name        = var.instance_network_internal
    fixed_ip_v4 = var.instance_internal_fixed_ip == "" ? "" : "${var.instance_internal_fixed_ip}${count.index + 1}"
  }
}

# Port Neutron de chaque instance (pour associer l'IP flottante en provider 3.x)
data "openstack_networking_port_v2" "instance_port" {
  count     = (var.public_floating_ip || var.public_floating_ip_fixed != "") ? var.instance_count : 0
  device_id = openstack_compute_instance_v2.instance[count.index].id
}

# IP flottante créée et associée via port_id (compatible provider 3.x ; 1.x accepte aussi)
resource "openstack_networking_floatingip_v2" "floatip_1_random" {
  count      = var.public_floating_ip && var.public_floating_ip_fixed == "" ? var.instance_count : 0
  pool       = var.instance_network_external_name
  subnet_ids = data.openstack_networking_subnet_ids_v2.ext_subnets[0].ids
  port_id    = data.openstack_networking_port_v2.instance_port[count.index].id
}

# IP flottante existante (fixed) : association via Neutron (provider 3.x)
data "openstack_networking_floatingip_v2" "existing_fip" {
  count   = var.public_floating_ip_fixed != "" ? 1 : 0
  address = var.public_floating_ip_fixed
}
resource "openstack_networking_floatingip_associate_v2" "fip_assoc_fixed" {
  count        = var.public_floating_ip_fixed != "" ? 1 : 0
  floating_ip  = data.openstack_networking_floatingip_v2.existing_fip[0].address
  port_id      = data.openstack_networking_port_v2.instance_port[0].id
}

locals {
  device_names = ["/dev/sdb","/dev/sdc","/dev/sdd","/dev/sde","/dev/sdf","/dev/sdg"]
}

locals {
  instance_volume_map =  merge([

    for idxi, instance in openstack_compute_instance_v2.instance.*:
    {
      for idxv in range(var.instance_volumes_count):
        "${instance.name}-volume-${idxv}" => {
            instance_name     = instance.name
            instance_id       = instance.id
            volume_name       = "${instance.name}-volume-${idxv}"
            device            = local.device_names[idxv]
          }
    }
    
  ]...)
}
