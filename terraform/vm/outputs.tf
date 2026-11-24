# terraform/vm — izlazi.

output "vm_ips" {
  description = "Statičke IP adrese virtuelnih mašina"
  value       = { for k, v in var.vms : k => v.ip }
}

output "segments" {
  description = "Podmreže segmenata"
  value       = { for k, v in var.segments : k => v.cidr }
}

output "inventory_path" {
  description = "Putanja generisanog Ansible inventara"
  value       = local_file.inventory.filename
}
