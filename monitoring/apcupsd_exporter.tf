resource "kubernetes_deployment" "apcupsd_exporter" {
  metadata {
    name      = "apcupsd-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "apcupsd-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "apcupsd-exporter"
        }

        annotations = {
            prometheus_io_scrape = true
            prometheus_io_port = "9162"
        }
      }
      spec {
                node_selector = {
          "kubernetes.io/arch" = "amd64"
        }
        container {
          name    = "apcupsd-exporter"
          image   = "b3vis/apcupsd_exporter:latest"
          env {
            name  = "APCUPSDADDR"
            value = "homelab.lan:3551"
          }
          port {
            container_port = 9162
            protocol       = "TCP"
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "apcupsd_exporter" {
  metadata {
    name      = "apcupsd"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "apcupsd-exporter"
    }
    port {
      port = 9162
    }
  }
}



