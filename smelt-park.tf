module "smelt_park" {
  source = "./claude-park"
  name   = "smelt-park"
}

output "smelt_park_kubeconfig" {
  sensitive = true
  value     = module.smelt_park.claude_park_kubeconfig
}

output "smelt_park_daemon_tls_secret" {
  value = module.smelt_park.claude_park_daemon_tls_secret
}

output "smelt_park_ca_cert" {
  sensitive = true
  value     = module.smelt_park.claude_park_ca_cert
}

output "smelt_park_server_cert" {
  value = module.smelt_park.claude_park_server_cert
}

output "smelt_park_client_cert" {
  sensitive = true
  value     = module.smelt_park.claude_park_client_cert
}

output "smelt_park_client_key" {
  sensitive = true
  value     = module.smelt_park.claude_park_client_key
}
