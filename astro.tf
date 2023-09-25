
module "astro_dns" {
  source = "./pi-hole-service"

  record = "astro.homelab"
  ip     = "192.168.1.161"
}

module "astro" {
  source = "./astro"

  namespace    = "astro"
  telescope_pc = "astro.homelab"
}