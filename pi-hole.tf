locals {
  pi_hole_fqdn = "pihole.homelab"
}

module "pi_hole" {
  source = "./pi-hole"
  fqdn   = local.pi_hole_fqdn
}

module "pi_hole_dns" {
  source = "./pi-hole-service"

  record  = local.pi_hole_fqdn
  ingress = module.pi_hole.ingress
}
