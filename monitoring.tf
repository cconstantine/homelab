module "monitoring" {
  source     = "./monitoring"
  domain     = "homelab"
  tls_domain = "constantlee.us"

  strata_api_key = module.ai.strata_api_key
}
