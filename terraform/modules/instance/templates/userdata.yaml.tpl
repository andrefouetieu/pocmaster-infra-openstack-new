#cloud-config
users:
  - default
  - name: ${instance_ssh_user}
    primary_group: ${instance_ssh_user}
    groups: [sudo, adm]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh-authorized-keys:
    - ${instance_ssh_key}
