# Keypair pour le cluster K8s (stack 02 indépendant).
resource "openstack_compute_keypair_v2" "cluster_key" {
  name       = "cluster_key"
  public_key = var.ssh_public_key_default_user
}
