module "monitoring" {
  source = "./monitoring"
  domain = "internal"
}

module "monitoring_dns" {
  for_each = module.monitoring.public_services
  source   = "./pi-hole-service"

  record  = each.key
  ingress = each.value
}
