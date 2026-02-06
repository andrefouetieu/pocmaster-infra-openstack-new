
module "consul" {
  source                      = "../modules/instance"
  instance_count              = 3
  instance_name               = "consul"
  instance_key_pair           = "default_key"
  instance_security_groups    = ["consul", "ssh-internal", "default"]
  instance_network_internal   = var.network_internal_dev
  instance_ssh_key = var.ssh_public_key_default_user
  public_floating_ip = false
  metadatas                   = {
    environment          = "dev"
  }
}
      