# Extract with:
#   terraform output -raw claude_park_kubeconfig > ~/park-kubeconfig.yaml && chmod 600 ~/park-kubeconfig.yaml
output "claude_park_kubeconfig" {
  description = "kubeconfig scoped to the claude-park namespace via the park ServiceAccount's token."
  sensitive   = true
  value = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "claude-park"
    clusters = [{
      name = "claude-park"
      cluster = {
        server                     = "https://${var.api_server_ip}:6443"
        certificate-authority-data = base64encode(kubernetes_secret.park_token.data["ca.crt"])
      }
    }]
    contexts = [{
      name = "claude-park"
      context = {
        cluster   = "claude-park"
        user      = "park"
        namespace = kubernetes_namespace.claude_park.metadata.0.name
      }
    }]
    users = [{
      name = "park"
      user = {
        token = kubernetes_secret.park_token.data["token"]
      }
    }]
  })
}

output "claude_park_daemon_tls_secret" {
  description = "Name of the in-cluster Secret holding the docker daemon CA cert, server cert, and server key, for the Mac-side pod spec to mount."
  value       = kubernetes_secret.claude_park_daemon_tls.metadata.0.name
}

output "claude_park_ca_cert" {
  description = "CA cert (PEM). Populate the Mac docker context's cert directory as ca.pem."
  sensitive   = true
  value       = tls_self_signed_cert.ca.cert_pem
}

output "claude_park_server_cert" {
  description = "Server cert (PEM), for SAN verification: terraform output -raw claude_park_server_cert | openssl x509 -noout -ext subjectAltName"
  value       = tls_locally_signed_cert.server.cert_pem
}

output "claude_park_client_cert" {
  description = "Client cert (PEM). Populate the Mac docker context's cert directory as cert.pem."
  sensitive   = true
  value       = tls_locally_signed_cert.client.cert_pem
}

output "claude_park_client_key" {
  description = "Client private key (PEM). Populate the Mac docker context's cert directory as key.pem."
  sensitive   = true
  value       = tls_private_key.client.private_key_pem
}
