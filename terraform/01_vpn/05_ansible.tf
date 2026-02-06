
resource "null_resource" "openvpn_server" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<-EOT
      sleep 20s;
      echo > /tmp/openvpn.ini;
      echo "[openvpn]" | tee -a /tmp/openvpn.ini;
      echo "${module.openvpn.instance_compute_name[0]} ansible_host=${module.openvpn.instance_external_ip_random[0]}" | tee -a /tmp/openvpn.ini;
      ANSIBLE_CONFIG=../../ansible/ansible.cfg ansible-playbook -u xavki -i /tmp/openvpn.ini --private-key ~/.ssh/id_rsa ../../ansible/openvpn_server.yml;
      rm -f /tmp/openvpn.ini;
    EOT
  }
    depends_on = [module.openvpn,module.network_dev]
}

resource "null_resource" "create_new_vpn_client" {
  for_each = toset(var.vpn_user_list)
    triggers = {
      name = each.value
      always_run = timestamp()
    }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo > /tmp/openvpn.ini;
      echo "[openvpn]" | tee -a /tmp/openvpn.ini;
      echo "${module.openvpn.instance_compute_name[0]} ansible_host=${module.openvpn.instance_external_ip_random[0]}" | tee -a /tmp/openvpn.ini;
      ANSIBLE_CONFIG=../../ansible/ansible.cfg ansible-playbook -u xavki -i /tmp/openvpn.ini --private-key ~/.ssh/id_rsa -e vpn_user_list=${each.value} ../../ansible/openvpn_client.yml;
      rm -f /tmp/openvpn.ini;
    EOT
  }
  depends_on = [null_resource.openvpn_server,module.openvpn,module.network_dev]
}
