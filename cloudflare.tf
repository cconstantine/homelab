variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

module "cloudflare" {
  source     = "./cloudflare"
  account_id = var.cloudflare_account_id
  domain     = "constantlee.us"
}
