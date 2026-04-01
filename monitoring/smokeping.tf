resource "kubernetes_deployment" "smokeping_exporter" {
  metadata {
    name      = "smokeping-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "smokeping-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "smokeping-exporter"
        }
      }
      spec {
        container {
          name    = "smokeping-exporter"
          image   = "quay.io/superq/smokeping-prober:latest"
          command = ["smokeping_prober", "google.com"]
          port {
            container_port = 9374
            protocol       = "TCP"
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "smokeping_exporter" {
  metadata {
    name      = "smokeping"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "smokeping-exporter"
    }
    port {
      port = 9374
    }
  }
}



