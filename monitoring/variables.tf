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

# htpasswd line(s) for the BasicAuth on Prometheus's /-/, /api/v1/admin and
# /api/v1/write ingress paths (SME-922), e.g. the output of
#   htpasswd -nbB promadmin '<password>'
# (bcrypt, $2y$). No default: an unset value fails the plan before anything
# changes.
variable "prometheus_admin_basic_auth" {
  type      = string
  sensitive = true
}
