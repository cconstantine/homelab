resource "kubernetes_deployment" "speedtest_exporter" {
  metadata {
    name      = "speedtest-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "speedtest-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "speedtest-exporter"
        }
      }
      spec {
        container {
          name  = "speedtest-exporter"
          image = "miguelndecarvalho/speedtest-exporter:latest"
          port {
            container_port = 9798
            protocol = "TCP"
          }
          env {
            name = "SPEEDTEST_PORT"
            value = "9798"
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "speedtest_exporter" {
  metadata {
    name      = "speedtest"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "speedtest-exporter"
    }
    port {
      port = 9798
    }
  }
}



