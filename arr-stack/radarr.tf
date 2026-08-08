resource "kubernetes_persistent_volume" "radarr_config" {
  metadata {
    name = "arr-radarr-config"
    labels = {
      type = "local"
      app  = "arr"
      use  = "radarr-config"
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
        path = "/storage/arr/radarr/config"
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

resource "kubernetes_persistent_volume_claim" "radarr_config" {
  metadata {
    name      = "radarr-config"
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
        use  = "radarr-config"
      }
    }
  }
}

resource "kubernetes_service" "radarr" {
  metadata {
    name      = "radarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "radarr"
    }
    port {
      port        = 7878
      target_port = 7878
    }
  }
}

resource "kubernetes_stateful_set" "radarr" {
  wait_for_rollout = false
  metadata {
    name      = "radarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "radarr"
      }
    }
    service_name = kubernetes_service.radarr.metadata.0.name

    template {
      metadata {
        labels = {
          name = "radarr"
        }
      }
      spec {
        container {
          name              = "radarr"
          image             = "lscr.io/linuxserver/radarr:latest"
          image_pull_policy = "Always"

          port {
            container_port = 7878
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
            name       = "movies"
            mount_path = "/movies"
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.radarr_config.metadata.0.name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.downloads.metadata.0.name
          }
        }

        volume {
          name = "movies"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.movies.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "radarr" {
  metadata {
    name      = "radarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "radarr.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.radarr.metadata.0.name
              port {
                number = 7878
              }
            }
          }
        }
      }
    }

  }
}

resource "kubernetes_ingress_v1" "radarr_tls" {
  metadata {
    name      = "radarr-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "radarr.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.radarr.metadata.0.name
              port {
                number = 7878
              }
            }
          }
        }
      }
    }
  }
}

module "radarr_dns" {
  source = "../pi-hole-service"

  record  = "radarr.${var.domain}"
  ingress = kubernetes_ingress_v1.radarr
}
