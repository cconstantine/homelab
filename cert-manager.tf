module "cert_manager" {
  source               = "./certmanager"
  cloudflare_api_token = var.cloudflare_api_token
  acme_email           = "cconstan@gmail.com"
  tls_domain           = "constantlee.us"
}
