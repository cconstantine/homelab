module "monitoring" {
  source = "./monitoring"
  domain = "internal"
}

module "monitoring_dns" {
  source         = "./pi-hole-entry"
  pi_hole_module = module.pi_hole
  record         = "grafana.internal"
  ip             = module.monitoring.grafana_ingress.status.0.load_balancer.0.ingress.0.ip
  ingress        = module.monitoring.public_services["grafana.internal"]
}
