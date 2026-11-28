# One htpasswd line for Prometheus's admin/lifecycle ingress paths (SME-922):
# set TF_VAR_prometheus_admin_basic_auth to the output of
#   htpasswd -nbB promadmin '<password>'
variable "prometheus_admin_basic_auth" {
  type      = string
  sensitive = true
}

module "monitoring" {
  source     = "./monitoring"
  domain     = "homelab"
  tls_domain = "constantlee.us"

  strata_api_key              = module.ai.strata_api_key
  prometheus_admin_basic_auth = var.prometheus_admin_basic_auth
}
