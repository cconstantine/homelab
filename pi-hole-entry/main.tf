locals {
  ips = toset(flatten([for stat in var.ingress.status : [for lb in stat.load_balancer : lb.ingress.*.ip]]))
}

resource "pihole_dns_record" "record" {
  for_each = local.ips
  domain = var.record
  ip     = each.value
}
