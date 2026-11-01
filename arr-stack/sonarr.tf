resource "kubernetes_persistent_volume" "sonarr_config" {
  metadata {
    name = "arr-sonarr-config"
    labels = {
      type = "local"
      app  = "arr"
      use  = "sonarr-config"
    }
  }
  spec {
    capacity = {
      storage = "1Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/arr/sonarr/config"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.config_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "sonarr_config" {
  metadata {
    name      = "sonarr-config"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.local_storage_class
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    selector {
      match_labels = {
        type = "local"
        app  = "arr"
        use  = "sonarr-config"
      }
    }
  }
}

resource "kubernetes_service" "sonarr" {
  metadata {
    name      = "sonarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "sonarr"
    }
    port {
      port        = 8989
      target_port = 8989
    }
  }
}

resource "kubernetes_stateful_set" "sonarr" {
  wait_for_rollout = false
  metadata {
    name      = "sonarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "sonarr"
      }
    }
    service_name = kubernetes_service.sonarr.metadata.0.name

    template {
      metadata {
        labels = {
          name = "sonarr"
        }
      }
      spec {
        container {
          name = "sonarr"

          resources {
            requests = {
              cpu    = "10m"
              memory = "240Mi"
            }
            limits = {
              memory = "384Mi"
            }
          }
          image             = "lscr.io/linuxserver/sonarr:latest"
          image_pull_policy = "Always"

          port {
            container_port = 8989
          }

          env {
            name  = "PUID"
            value = local.puid
          }
          env {
            name  = "PGID"
            value = local.pgid
          }
          env {
            name  = "TZ"
            value = "America/Los_Angeles"
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }

          volume_mount {
            name       = "tv"
            mount_path = "/tv"
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sonarr_config.metadata.0.name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.downloads.metadata.0.name
          }
        }

        volume {
          name = "tv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.tv.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "sonarr" {
  metadata {
    name      = "sonarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "sonarr.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.sonarr.metadata.0.name
              port {
                number = 8989
              }
            }
          }
        }
      }
    }

  }
}

resource "kubernetes_ingress_v1" "sonarr_tls" {
  metadata {
    name      = "sonarr-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "sonarr.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.sonarr.metadata.0.name
              port {
                number = 8989
              }
            }
          }
        }
      }
    }
  }
}

module "sonarr_dns" {
  source = "../pi-hole-service"

  record  = "sonarr.${var.domain}"
  ingress = kubernetes_ingress_v1.sonarr
}
