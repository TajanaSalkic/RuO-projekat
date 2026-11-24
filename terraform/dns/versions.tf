# terraform/dns — DNS zapisi servisa.
terraform {
  required_version = ">= 1.5"
  required_providers {
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.4"
    }
  }
}

# Provider šalje RFC 2136 dinamičke UPDATE poruke našem BIND-u, potpisane TSIG ključem ruo-tf.
provider "dns" {
  update {
    server        = var.dns_server
    key_name      = "ruo-tf."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret
  }
}
