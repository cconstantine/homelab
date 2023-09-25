locals {
  ip = var.ingress != null ? var.ingress.status.0.load_balancer.0.ingress.0.ip : var.ip
}

resource "pihole_dns_record" "record" {
  domain = var.record
  ip = local.ip
}
