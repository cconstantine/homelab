# Grafana Alloy: per-node log shipper. Tails /var/log/pods for pods on its own
# node and pushes to Loki (loki.tf). Config: config/alloy.river.
resource "kubernetes_service_account" "alloy" {
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

resource "kubernetes_cluster_role" "alloy" {
  metadata {
    name = "alloy"
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "alloy" {
  metadata {
    name = "alloy"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.alloy.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.alloy.metadata.0.name
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

resource "kubernetes_config_map" "alloy" {
  metadata {
    name      = "alloy-${sha1(file("${path.module}/config/alloy.river"))}"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "config.alloy" = file("${path.module}/config/alloy.river")
  }
}

resource "kubernetes_daemonset" "alloy" {
  wait_for_rollout = false
  metadata {
    name      = "alloy"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector {
      match_labels = {
        name = "alloy"
      }
    }
    template {
      metadata {
        labels = {
          name = "alloy"
        }
        annotations = {
          prometheus_io_scrape = true
          prometheus_io_port   = "12345"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.alloy.metadata.0.name

        # Runs on every node, including ryzen (tainted dedicated=strata).
        toleration {
          key      = "dedicated"
          operator = "Equal"
          value    = "strata"
          effect   = "NoSchedule"
        }

        container {
          name  = "alloy"
          image = "grafana/alloy:v1.21.3"
          args = [
            "run",
            "/etc/alloy/config.alloy",
            "--server.http.listen-addr=0.0.0.0:12345",
            "--storage.path=/var/lib/alloy/data",
            "--disable-reporting",
          ]

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          port {
            name           = "http"
            container_port = 12345
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "96Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }

          security_context {
            run_as_user = 0
          }

          volume_mount {
            name       = "alloy-config"
            mount_path = "/etc/alloy"
          }
          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }
          # Positions file: survives restarts so logs aren't re-shipped.
          volume_mount {
            name       = "alloy-data"
            mount_path = "/var/lib/alloy/data"
          }
        }

        volume {
          name = "alloy-config"
          config_map {
            name = kubernetes_config_map.alloy.metadata.0.name
          }
        }
        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }
        volume {
          name = "alloy-data"
          host_path {
            path = "/var/lib/alloy"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }
}
