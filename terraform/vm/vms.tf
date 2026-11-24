# terraform/vm — bazna slika, diskovi, cloud-init i domeni.

# Bazna slika se preuzima jednom; disk svake VM je njen copy-on-write potomak (nemutabilna infra).
resource "libvirt_volume" "base" {
  name   = "ruo-noble-base.qcow2"
  pool   = var.libvirt_pool
  format = "qcow2"
  source = var.base_image_url
}

resource "libvirt_volume" "disk" {
  for_each       = var.vms
  name           = "${each.key}.qcow2"
  pool           = var.libvirt_pool
  base_volume_id = libvirt_volume.base.id
  size           = 10 * 1024 * 1024 * 1024 # 10 GiB
}

# cloud-init: korisnik 'student' sa SSH ključem, bez lozinke + statička mreža.
resource "libvirt_cloudinit_disk" "init" {
  for_each = var.vms
  name     = "${each.key}-init.iso"
  pool     = var.libvirt_pool

  user_data = templatefile("${path.module}/../../cloud-init/user-data.tftpl", {
    hostname = each.key
    domain   = var.dns_domain
    ssh_key  = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })

  network_config = templatefile("${path.module}/../../cloud-init/network-config.tftpl", {
    ip          = each.value.ip
    prefix      = 24
    gateway     = var.segments[each.value.segment].gateway
    nameservers = join(", ", var.bootstrap_dns)
  })
}

resource "libvirt_domain" "vm" {
  for_each  = var.vms
  name      = each.key
  memory    = each.value.memory
  vcpu      = each.value.vcpu
  autostart = true
  cloudinit = libvirt_cloudinit_disk.init[each.key].id

  disk {
    volume_id = libvirt_volume.disk[each.key].id
  }

  network_interface {
    network_id     = libvirt_network.seg[each.value.segment].id
    wait_for_lease = false # statičke adrese (nema DHCP lease-a); IP znamo iz var.vms
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}
