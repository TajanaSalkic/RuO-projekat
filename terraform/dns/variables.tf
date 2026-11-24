variable "dns_server" {
  description = "Adresa BIND servera koji prima dinamičke updejte"
  type        = string
  default     = "10.40.0.53"
}

variable "zone" {
  description = "Zona projekta (sa završnom tačkom)"
  type        = string
  default     = "ruo.lab."
}

variable "tsig_secret" {
  description = "TSIG tajna ključa ruo-tf (iz ansible-vault-a; prosljeđuje je Makefile preko TF_VAR_tsig_secret)"
  type        = string
  sensitive   = true
}

# Servisi (segmenti web/app/db).
variable "services" {
  type = map(list(string))
  default = {
    web = ["10.40.1.10"]
    app = ["10.40.2.10"]
    db  = ["10.40.3.10"]
  }
}
