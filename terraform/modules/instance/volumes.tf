
resource "openstack_blockstorage_volume_v2" "volumes" {
  for_each        = local.instance_volume_map

  name            = each.value.volume_name
  size            = var.instance_volumes_size
  volume_type     = var.instance_volumes_type
}

resource "openstack_compute_volume_attach_v2" "attached" {
  for_each      = local.instance_volume_map
  
  instance_id   = each.value.instance_id
  device        = each.value.device
  volume_id     = openstack_blockstorage_volume_v2.volumes[each.key].id
  # Prevent re-creation
  lifecycle {
    ignore_changes = [volume_id, instance_id, device]
  }
}

