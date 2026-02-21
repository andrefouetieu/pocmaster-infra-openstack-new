# Applique les rôles Ansible k3s_server (master) et k3s_agent (workers) via le playbook k8s_cluster.yml.
# Même principe que 01_vpn/05_ansible.tf pour le VPN.
# Désactiver avec run_k8s_ansible_after_apply = false si la machine qui exécute Terraform ne peut pas joindre le cluster.
#
# Quand le master a une IP flottante et que les workers n'en ont pas, la machine qui lance Terraform
# ne peut pas joindre les workers (IP privées 10.0.2.x). On configure alors Ansible pour utiliser le
# master comme bastion (ProxyCommand) pour atteindre les workers.

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

  triggers = {
    always_run = timestamp()
  }

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
      ANSIBLE_CONFIG=../../ansible/ansible.cfg ansible-playbook \
        -u ${var.vm_ssh_user} -i $INI --private-key ~/.ssh/id_rsa \
        ../../ansible/k8s_cluster.yml
      rm -f $INI
    EOT
  }

  depends_on = [module.k8s_master, module.k8s_worker]
}
