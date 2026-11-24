# terraform/vm — segmentirane libvirt mreže u ROUTE modu.
# Route mod: host usmjerava između segmenata; stroga izolacija se nameće nftables-om
# na hostu. DHCP je isključen — adrese su statičke preko cloud-init network-config.
# DNS unutar libvirt mreže je isključen jer imenovanje radi BIND.

resource "libvirt_network" "seg" {
  for_each = var.segments

  name      = "ruo-${each.key}"
  mode      = "route"
  addresses = [each.value.cidr]
  autostart = true

  dns {
    enabled = false
  }

  dhcp {
    enabled = false
  }
}
