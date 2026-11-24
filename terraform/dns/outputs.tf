output "records" {
  description = "Imena koja su kreirana u zoni"
  value = concat(
    [for k, _ in var.services : "${k}.${var.zone}"],
    ["www.${var.zone}"]
  )
}
