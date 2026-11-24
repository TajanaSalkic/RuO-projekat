# terraform/dns — servisni DNS zapisi kao Terraform resursi.
# Isti obrazac vrijedi za DNS u oblaku (Route 53, Azure DNS, Cloudflare): mijenja se samo provider.

resource "dns_a_record_set" "svc" {
  for_each  = var.services
  zone      = var.zone
  name      = each.key
  addresses = each.value
  ttl       = 300
}

resource "dns_cname_record" "www" {
  zone  = var.zone
  name  = "www"
  cname = "web.${var.zone}"
  ttl   = 300
}
