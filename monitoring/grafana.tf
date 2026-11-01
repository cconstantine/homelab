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

resource "kubernetes_config_map" "grafana_dashboard_providers" {
  metadata {
    name      = "grafana-dashboard-providers"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "dashboards.yaml" = file("${path.module}/config/grafana-dashboards.yaml")
  }
}

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    for f in fileset("${path.module}/dashboards", "*.json") : f => file("${path.module}/dashboards/${f}")
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
          name = "grafana"

          resources {
            requests = {
              cpu    = "40m"
              memory = "1728Mi"
            }
            limits = {
              memory = "3Gi"
            }
          }
          image = "grafana/grafana:13.2.4"

          volume_mount {
            mount_path = "/var/lib/grafana"
            name       = "grafana-data"
          }
          volume_mount {
            mount_path = "/etc/grafana/provisioning/datasources"
            name       = "grafana-datasources"
          }
          volume_mount {
            mount_path = "/etc/grafana/provisioning/dashboards"
            name       = "grafana-dashboard-providers"
          }
          volume_mount {
            mount_path = "/etc/grafana/dashboards"
            name       = "grafana-dashboards"
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
          name = "grafana-dashboard-providers"
          config_map {
            name = kubernetes_config_map.grafana_dashboard_providers.metadata.0.name
          }
        }
        volume {
          name = "grafana-dashboards"
          config_map {
            name = kubernetes_config_map.grafana_dashboards.metadata.0.name
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
