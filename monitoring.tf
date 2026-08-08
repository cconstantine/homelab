module "monitoring" {
  source     = "./monitoring"
  domain     = "homelab"
  tls_domain = "constantlee.us"
}
