module "jellyfin" {
  source     = "./jellyfin"
  domain     = "homelab"
  tls_domain = "constantlee.us"
}
