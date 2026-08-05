module "claude_park" {
  source = "./claude-park"
}

output "claude_park_kubeconfig" {
  sensitive = true
  value     = module.claude_park.claude_park_kubeconfig
}

output "claude_park_daemon_tls_secret" {
  value = module.claude_park.claude_park_daemon_tls_secret
}

output "claude_park_ca_cert" {
  sensitive = true
  value     = module.claude_park.claude_park_ca_cert
}

output "claude_park_server_cert" {
  value = module.claude_park.claude_park_server_cert
}

output "claude_park_client_cert" {
  sensitive = true
  value     = module.claude_park.claude_park_client_cert
}

output "claude_park_client_key" {
  sensitive = true
  value     = module.claude_park.claude_park_client_key
}
