# terraform/vm — Ansible inventory kao resurs (DO-6): generisan iz Terraform definicija,
# bez ručnog koraka. Grupe [dns][web][app][db]. Fajl je u .gitignore (nije u Gitu).

locals {
  # segment -> Ansible grupa
  seg_to_group = {
    mgmt = "dns"
    web  = "web"
    app  = "app"
    db   = "db"
  }

  inv_groups = {
    for seg, grp in local.seg_to_group : grp => [
      for name, vm in var.vms :
      "${name} ansible_host=${vm.ip} ansible_user=student"
      if vm.segment == seg
    ]
  }

  inventory_content = join("\n", concat(
    ["# GENERISAN Terraformom (terraform/vm)."],
    flatten([
      for grp, lines in local.inv_groups : concat(["", "[${grp}]"], lines)
    ]),
    [
      "",
      "[all:vars]",
      "ansible_ssh_private_key_file=~/.ssh/id_ed25519",
      "ansible_python_interpreter=/usr/bin/python3",
      "ansible_ssh_common_args=-o StrictHostKeyChecking=accept-new",
      "" # završni novi red
    ]
  ))
}

resource "local_file" "inventory" {
  filename        = "${path.module}/../../ansible/inventory.ini"
  content         = local.inventory_content
  file_permission = "0644"
}
