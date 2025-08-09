module "homeassistant_dns" {
  source   = "./pi-hole-service"

  record  = "homeassistant.homelab"
  ip = "192.168.8.228"
}
