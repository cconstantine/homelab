locals {
  ip = var.ingress.status.0.load_balancer.0.ingress.0.ip
}

resource "pihole_dns_record" "record" {
  domain = var.record
  ip = local.ip
}
