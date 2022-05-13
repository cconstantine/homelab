module "pi_hole" {
  source ="./pi-hole"
}


moved {
  from = kubernetes_namespace.pi_hole
  to   = module.pi_hole.kubernetes_namespace.pi_hole
}

moved {
  from = random_password.password
  to   = module.pi_hole.random_password.password
}

moved {
  from = kubernetes_persistent_volume_claim.etc_pihole
  to   = module.pi_hole.kubernetes_persistent_volume_claim.etc_pihole
}

moved {
  from = kubernetes_persistent_volume_claim.dnsmasq_pihole
  to   = module.pi_hole.kubernetes_persistent_volume_claim.dnsmasq_pihole
}

moved {
  from = kubernetes_stateful_set.pi_hole
  to   = module.pi_hole.kubernetes_stateful_set.pi_hole
}

moved {
  from = kubernetes_service.pihole_web
  to = module.pi_hole.kubernetes_service.pihole_web
}

moved {
  from = kubernetes_service.pihole_dns
  to = module.pi_hole.kubernetes_service.pihole_dns
}

moved {
  from = kubernetes_ingress.pihole_ingress
  to = module.pi_hole.kubernetes_ingress.pihole_ingress
}
