resource "kubernetes_deployment" "blackbox_exporter" {
  metadata {
    name      = "blackbox-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 2
    selector {
      match_labels = {
        name = "blackbox-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "blackbox-exporter"
        }
      }
      spec {
        # amd64 nodes only: on an arm node (pixo-8, since removed) its DNS lookups
        # timed out. Untested on xavier.
        node_selector = {
          "kubernetes.io/arch" = "amd64"
        }

        container {
          name = "blackbox-exporter"

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              memory = "32Mi"
            }
          }
          image = "prom/blackbox-exporter:latest"
        }
      }
    }
  }
}


resource "kubernetes_service" "blackbox_exporter" {
  metadata {
    name      = "blackbox-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "blackbox-exporter"
    }
    port {
      port = 9115
    }
  }
}
