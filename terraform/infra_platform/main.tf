# infra_platform : cluster K8s pour outils plateforme (Vault, Kafka, etc.).
# deploy_vpn=true : OpenVPN installé sur le master (accès cluster via VPN).
# install_vault=true : Vault installé via Ansible/Helm après création du cluster.

module "cluster" {
  count  = var.deploy_k8s ? 1 : 0
  source = "../modules/cluster"

  name_prefix                 = var.infra_name
  cluster_network_name        = "${var.infra_name}-cluster"
  network_subnet_cidr         = var.cluster_subnet_cidr
  network_external_id         = var.network_external_id
  network_external_name       = var.network_external_name
  ssh_public_key_default_user = var.ssh_public_key_default_user
  vm_ssh_user                 = var.vm_ssh_user
  instance_image_id           = var.instance_image_id
  instance_flavor_name        = var.instance_flavor_name
  k8s_worker_count            = var.k8s_worker_count
  k8s_master_floating_ip      = var.k8s_master_floating_ip
  run_k8s_ansible_after_apply = var.run_k8s_ansible_after_apply
  deploy_vpn                  = var.deploy_vpn
  vpn_user_list               = var.vpn_user_list
  install_vault               = var.install_vault
  ansible_base_path           = "${path.module}/../../ansible"
}
