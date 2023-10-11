resource "kubernetes_deployment" "veil_exporter" {
  metadata {
    name      = "veil"
    namespace = kubernetes_namespace.veil.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "veil"
      }
    }
    template {
      metadata {
        labels = {
          name = "veil"
        }
      }
      spec {
        container {
          name  = "veil"
          image = "ghcr.io/cconstantine/veil:latest"
          port {
            container_port = 80
            protocol = "TCP"
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "veil" {
  metadata {
    name      = "veil"
    namespace = kubernetes_namespace.veil.metadata.0.name
  }
  spec {
    selector = {
      name = "veil"
    }
    port {
      port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "veil" {
  metadata {
    name      = "veil-ingress"
    namespace = kubernetes_namespace.veil.metadata.0.name
  }

  spec {
    rule {
      host = "veil.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.veil.metadata.0.name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

module "veil_dns" {
  source   = "../pi-hole-service"

  record  = "veil.${var.domain}"
  ingress = kubernetes_ingress_v1.veil
}
