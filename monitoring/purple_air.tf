resource "kubernetes_deployment" "purple_air_exporter" {
  metadata {
    name      = "purple-air-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "purple-air-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "purple-air-exporter"
        }
      }
      spec {
        container {
          name  = "purple-air-exporter"
          image = "wbertelsen/purpleair-to-prometheus:latest"
          command = ["./purple_to_prom.py",
            "--sensor-ids",
            "71601"
          ]
          port {
            container_port = 9760
            protocol = "TCP"
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "purple_air_exporter" {
  metadata {
    name      = "purple-air"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
    annotations = {
      prometheus_io_scrape = true
    }
  }
  spec {
    selector = {
      name = "purple-air-exporter"
    }
    port {
      port = 9760
    }
  }
}



