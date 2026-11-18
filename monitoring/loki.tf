# Loki: log storage. Alloy (alloy.tf) ships pod logs here; Grafana reads it on
# 3100 via the provisioned data source (config/grafana-datasources.yaml).
resource "kubernetes_config_map" "loki" {
  metadata {
    name      = "loki-${sha1(file("${path.module}/config/loki.yaml"))}"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "loki.yaml" = file("${path.module}/config/loki.yaml")
  }
}

resource "kubernetes_deployment" "loki" {
  wait_for_rollout = false
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "loki"
      }
    }
    template {
      metadata {
        labels = {
          name = "loki"
        }
        annotations = {
          prometheus_io_scrape = true
          prometheus_io_port   = "3100"
        }
      }
      spec {
        node_selector = {
          "kubernetes.io/hostname" = "homelab"
        }

        init_container {
          name              = "init-chown-data"
          image             = "busybox:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["chown", "-R", "10001:10001", "/var/loki"]
          volume_mount {
            name       = "loki-data"
            mount_path = "/var/loki"
          }
        }

        container {
          name  = "loki"
          image = "grafana/loki:3.7.10"
          args  = ["-target=all", "-config.file=/etc/loki/loki.yaml"]

          port {
            name           = "http"
            container_port = 3100
          }
          port {
            name           = "grpc"
            container_port = 9095
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "http"
            }
            initial_delay_seconds = 15
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "512Mi"
            }
            limits = {
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "loki-config"
            mount_path = "/etc/loki"
          }
          volume_mount {
            name       = "loki-data"
            mount_path = "/var/loki"
          }
        }

        volume {
          name = "loki-config"
          config_map {
            name = kubernetes_config_map.loki.metadata.0.name
          }
        }
        volume {
          name = "loki-data"
          # homelab's large /storage disk (same as Prometheus).
          host_path {
            path = "/storage/loki"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "loki"
    }
    port {
      name = "http"
      port = 3100
    }
  }
}

output "loki_push_endpoint" {
  value = "http://${kubernetes_service.loki.metadata.0.name}.${kubernetes_namespace.monitoring.metadata.0.name}.svc.cluster.local:3100/loki/api/v1/push"
}
