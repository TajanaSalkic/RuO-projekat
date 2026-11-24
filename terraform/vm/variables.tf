# terraform/vm — ulazne varijable.

variable "libvirt_pool" {
  description = "libvirt storage pool (kreira ga scripts/00-setup.sh)"
  type        = string
  default     = "default"
}

variable "base_image_url" {
  description = "Zvanična Ubuntu 24.04 (noble) cloud slika"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ssh_public_key_path" {
  description = "Javni SSH ključ koji cloud-init injektira "
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "dns_domain" {
  description = "Domena projekta"
  type        = string
  default     = "ruo.lab"
}

variable "bootstrap_dns" {
  description = "Resolveri za bootstrap prije nego BIND zaživi"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# Segmenti: svaki sloj u svojoj podmreži. Gateway = .1 (adresa libvirt bridge-a u route modu).
variable "segments" {
  type = map(object({
    cidr    = string
    gateway = string
  }))
  default = {
    mgmt = { cidr = "10.40.0.0/24", gateway = "10.40.0.1" }
    web  = { cidr = "10.40.1.0/24", gateway = "10.40.1.1" }
    app  = { cidr = "10.40.2.0/24", gateway = "10.40.2.1" }
    db   = { cidr = "10.40.3.0/24", gateway = "10.40.3.1" }
  }
}

# Virtuelne mašine: po jedna po sloju + namjenski DNS. Statičke adrese.
variable "vms" {
  type = map(object({
    segment = string
    ip      = string
    memory  = number # MiB
    vcpu    = number
  }))
  default = {
    "ruo-dns" = { segment = "mgmt", ip = "10.40.0.53", memory = 768, vcpu = 1 }
    "ruo-web" = { segment = "web", ip = "10.40.1.10", memory = 1024, vcpu = 1 }
    "ruo-app" = { segment = "app", ip = "10.40.2.10", memory = 1024, vcpu = 1 }
    "ruo-db"  = { segment = "db", ip = "10.40.3.10", memory = 1024, vcpu = 1 }
  }
}
