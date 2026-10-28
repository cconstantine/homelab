variable "domain" {
  type = string
}

variable "tls_domain" {
  type = string
}
# Bearer token for scraping strata-ryzen's /metrics (ai/strata.tf).
variable "strata_api_key" {
  type      = string
  sensitive = true
}
