resource "pihole_dns_record" "record" {
  domain = "homeassistant.homelab"
  ip     = "192.168.1.228"
}
