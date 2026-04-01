module "frigate" {
  source = "./frigate"
  domain = "homelab"
}

# module "prometheus_dns" {
#   source   = "./pi-hole-service"

#   record  = "frigate.homelab"
#   ip = "192.168.1.130"
# }
