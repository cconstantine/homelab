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
        container {
          name  = "blackbox-exporter"
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
