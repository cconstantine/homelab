resource "kubernetes_service" "srvr" {
  metadata {
    name      = "srvr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "srvr"
    }
    port {
      port = 8080
    }
  }
}

resource "kubernetes_stateful_set" "srvr" {
  wait_for_rollout = false
  metadata {
    name      = "srvr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "srvr"
      }
    }
    service_name = kubernetes_service.srvr.metadata.0.name

    update_strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels = {
          name = "srvr"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }
      spec {
        container {
          name = "srvr"

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "96Mi"
            }
          }
          image             = "ghcr.io/twinkle-astronomy/srvr:latest"
          image_pull_policy = "Always"


          env {
            name  = "PROMETHEUS_URL"
            value = "http://prometheus.monitoring.svc.cluster.local:9090"
          }
          env {
            name  = "DATABASE_URL"
            value = "sqlite:///data/data.db"
          }
          env {
            name  = "TZ"
            value = "America/Los_Angeles"
          }
          env {
            name  = "IMAGE_SIGNATURE_SECRET"
            value = "homelab"
          }

          volume_mount {
            name       = "srvr-data"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "srvr-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "srvr" {
  metadata {
    name      = "srvr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "srvr.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.srvr.metadata.0.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }

  }
}

resource "kubernetes_ingress_v1" "srvr_tls" {
  metadata {
    name      = "srvr-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "srvr.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.srvr.metadata.0.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

module "srvr_dns" {
  source = "../pi-hole-service"

  record  = "srvr.${var.domain}"
  ingress = kubernetes_ingress_v1.srvr
}
