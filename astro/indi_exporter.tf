


resource "kubernetes_deployment" "indi_exporter" {
  metadata {
    name      = "indi-exporter"
    namespace = kubernetes_namespace.astro.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "indi-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "indi-exporter"
        }
      }
      spec {
        container {
          name  = "indi-exporter"
          image = "ghcr.io/twinkle-astronomy/indi_exporter:v0.1.3"
          image_pull_policy = "Always"
          command = ["indi_exporter",
            "${var.telescope_pc}:7624",
          ]
          
          port {
            container_port = 9186
            protocol = "TCP"
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "indi_exporter" {
  metadata {
    name      = "indi-exporter"
    namespace = kubernetes_namespace.astro.metadata.0.name
    annotations = {
      prometheus_io_scrape = true
    }
  }
  spec {
    selector = {
      name = "indi-exporter"
    }
    port {
      port = 9186
    }
  }
}



