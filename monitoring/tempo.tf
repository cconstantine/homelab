# Tempo: trace storage for OTLP senders in the cluster (smelt, so far).
# Senders use the OTLP endpoints on the `tempo` service; Grafana reads it on
# 3200 via the provisioned data source (config/grafana-datasources.yaml).
resource "kubernetes_config_map" "tempo" {
  metadata {
    name      = "tempo-${sha1(file("${path.module}/config/tempo.yaml"))}"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "tempo.yaml" = file("${path.module}/config/tempo.yaml")
  }
}

resource "kubernetes_persistent_volume_claim" "tempo_data" {
  metadata {
    name      = "tempo-data"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "tempo" {
  wait_for_rollout = false
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "tempo"
      }
    }
    template {
      metadata {
        labels = {
          name = "tempo"
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
          command           = ["chown", "-R", "10001:10001", "/var/tempo"]
          volume_mount {
            name       = "tempo-data"
            mount_path = "/var/tempo"
          }
        }

        container {
          name  = "tempo"
          image = "grafana/tempo:3.1.0"
          args  = ["-target=all", "-config.file=/etc/tempo/tempo.yaml"]

          port {
            name           = "http"
            container_port = 3200
          }
          port {
            name           = "otlp-grpc"
            container_port = 4317
          }
          port {
            name           = "otlp-http"
            container_port = 4318
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "640Mi"
            }
            limits = {
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "tempo-config"
            mount_path = "/etc/tempo"
          }
          volume_mount {
            name       = "tempo-data"
            mount_path = "/var/tempo"
          }
        }

        volume {
          name = "tempo-config"
          config_map {
            name = kubernetes_config_map.tempo.metadata.0.name
          }
        }
        volume {
          name = "tempo-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.tempo_data.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "tempo" {
  metadata {
    name      = "tempo"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "tempo"
    }
    port {
      name = "http"
      port = 3200
    }
    port {
      name = "otlp-grpc"
      port = 4317
    }
    port {
      name = "otlp-http"
      port = 4318
    }
  }
}

output "tempo_otlp_http_endpoint" {
  value = "http://${kubernetes_service.tempo.metadata.0.name}.${kubernetes_namespace.monitoring.metadata.0.name}.svc.cluster.local:4318"
}
