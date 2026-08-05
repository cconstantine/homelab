# Mutual TLS for the per-park docker daemon (dind). Generated here, rather
# than left to dind's self-signed default, because dind's own cert only
# covers localhost/docker/container-id and fails against a LAN address.

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years; rotation is a manual chore

  subject {
    common_name  = "claude-park CA"
    organization = "claude-park"
  }

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
  ]
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name = "claude-park-daemon"
  }

  dns_names    = ["localhost"]
  ip_addresses = concat(var.node_ips, ["127.0.0.1"])
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem      = tls_cert_request.server.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name = "claude-park-client"
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem      = tls_cert_request.client.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

# Mounted by the Mac-side tooling into each park pod; dockerd is pointed at
# it with --tlsverify --tlscacert --tlscert --tlskey. The pod spec itself is
# not written here (see brief, scope boundary).
resource "kubernetes_secret" "claude_park_daemon_tls" {
  metadata {
    name      = "claude-park-daemon-tls"
    namespace = kubernetes_namespace.claude_park.metadata.0.name
  }

  data = {
    "ca.pem"          = tls_self_signed_cert.ca.cert_pem
    "server-cert.pem" = tls_locally_signed_cert.server.cert_pem
    "server-key.pem"  = tls_private_key.server.private_key_pem
  }
}
