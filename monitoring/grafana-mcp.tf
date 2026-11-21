# Grafana MCP server (github.com/grafana/mcp-grafana): gives MCP clients
# search/read over dashboards, PromQL/LogQL/TraceQL queries through Grafana's
# data sources, alert rules, etc. Served over streamable-http at
#   https://grafana-mcp.<tls_domain>/mcp            (LAN only; *.tls_domain -> 192.168.8.130)
#   http://grafana-mcp.monitoring.svc.cluster.local:8000/mcp
#
# Callers must send the bearer token:
#   kubectl -n monitoring get secret grafana-mcp -o jsonpath='{.data.MCP_GRAFANA_SERVER_TOKEN}' | base64 -d
# e.g. claude mcp add --transport http grafana https://grafana-mcp.constantlee.us/mcp \
#        --header "Authorization: Bearer <token>"
#
# Grafana credentials: none. The server talks to Grafana unauthenticated, so
# it gets the anonymous Viewer role (GF_AUTH_ANONYMOUS_ENABLED in grafana.tf),
# and --disable-write drops the create/update tools a Viewer can't use anyway.

resource "random_password" "grafana_mcp_server_token" {
  length  = 48
  special = false
}

resource "kubernetes_secret" "grafana_mcp" {
  metadata {
    name      = "grafana-mcp"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    MCP_GRAFANA_SERVER_TOKEN = random_password.grafana_mcp_server_token.result
  }
}

locals {
  grafana_mcp_hosts = [
    "grafana-mcp.${var.tls_domain}",
    "grafana-mcp.monitoring.svc.cluster.local:8000",
    "grafana-mcp.monitoring.svc:8000",
    "grafana-mcp.monitoring:8000",
  ]
}

resource "kubernetes_deployment" "grafana_mcp" {
  metadata {
    name      = "grafana-mcp"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "grafana-mcp"
      }
    }
    template {
      metadata {
        labels = {
          name = "grafana-mcp"
        }
      }
      spec {
        container {
          name  = "grafana-mcp"
          image = "grafana/mcp-grafana:2.3.0"
          args = [
            "--transport", "streamable-http",
            "--address", "0.0.0.0:8000",
            # Host/Origin allowlist on the MCP listener (DNS-rebinding guard).
            "--allowed-hosts", join(",", local.grafana_mcp_hosts),
            # Probes go to a side listener, which skips the Host check.
            "--healthz-address", "0.0.0.0:8081",
            "--usage-stats", "disabled",
            "--disable-write",
          ]

          env {
            name  = "GRAFANA_URL"
            value = "http://grafana.monitoring.svc.cluster.local:3000"
          }
          env {
            name = "MCP_GRAFANA_SERVER_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_mcp.metadata.0.name
                key  = "MCP_GRAFANA_SERVER_TOKEN"
              }
            }
          }

          port {
            name           = "mcp"
            container_port = 8000
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8081
            }
            period_seconds = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8081
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana_mcp" {
  metadata {
    name      = "grafana-mcp"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "grafana-mcp"
    }
    port {
      port        = 8000
      target_port = 8000
    }
  }
}

resource "kubernetes_ingress_v1" "grafana_mcp_tls" {
  metadata {
    name      = "grafana-mcp-ingress-tls"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "grafana-mcp.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.grafana_mcp.metadata.0.name
              port {
                number = 8000
              }
            }
          }
        }
      }
    }
  }
}
