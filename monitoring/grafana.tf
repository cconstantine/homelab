resource "kubernetes_persistent_volume_claim" "grafana_data" {
  metadata {
    name      = "grafana-data"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_config_map" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "datasources.yaml" = file("${path.module}/config/grafana-datasources.yaml")
  }
}

resource "kubernetes_deployment" "grafana" {
  timeouts {
    create = "2m"
    delete = "2m"
  }
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "grafana"
      }
    }
    template {
      metadata {
        labels = {
          name = "grafana"
        }
        annotations = {
          "checksum/datasources" = sha1(file("${path.module}/config/grafana-datasources.yaml"))
        }
      }
      spec {
        init_container {
          name              = "init-chown-data"
          image             = "busybox:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["chown", "-R", "472:472", "/var/lib/grafana"]
          volume_mount {
            mount_path = "/var/lib/grafana"
            name       = "grafana-data"
          }
        }
        container {
          name  = "grafana"
          image = "grafana/grafana:13.2.4"

          volume_mount {
            mount_path = "/var/lib/grafana"
            name       = "grafana-data"
          }
          volume_mount {
            mount_path = "/etc/grafana/provisioning/datasources"
            name       = "grafana-datasources"
          }
          env {
            name  = "GF_AUTH_ANONYMOUS_ENABLED"
            value = "true"
          }
        }
        volume {
          name = "grafana-datasources"
          config_map {
            name = kubernetes_config_map.grafana_datasources.metadata.0.name
          }
        }
        volume {
          name = "grafana-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana_data.metadata.0.name
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "grafana"
    }
    port {
      port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "grafana_ingress" {
  metadata {
    name      = "grafana-ingress"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  spec {
    rule {
      host = "grafana.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.grafana.metadata.0.name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

  }
}

resource "kubernetes_ingress_v1" "grafana_ingress_tls" {
  metadata {
    name      = "grafana-ingress-tls"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "grafana.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.grafana.metadata.0.name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
}

module "grafana_dns" {
  source = "../pi-hole-service"

  record  = "grafana.${var.domain}"
  ingress = kubernetes_ingress_v1.grafana_ingress
}
