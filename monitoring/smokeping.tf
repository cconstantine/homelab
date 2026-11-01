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
        # amd64 nodes only: on an arm node (pixo-8, since removed) its DNS lookups
        # timed out and it exited. Untested on xavier.
        node_selector = {
          "kubernetes.io/arch" = "amd64"
        }

        container {
          name = "smokeping-exporter"

          resources {
            requests = {
              cpu    = "10m"
              memory = "48Mi"
            }
            limits = {
              memory = "64Mi"
            }
          }
          image = "quay.io/superq/smokeping-prober:latest"
          command = [
            "smokeping_prober",
            "--buckets=0.001,0.002,0.004,0.006,0.008,0.010,0.012,0.014,0.016,0.018,0.020,0.025,0.030,0.040,0.050,0.075,0.100,0.150,0.200,0.300,0.500,1.000,2.000",
            "google.com",
          ]
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



