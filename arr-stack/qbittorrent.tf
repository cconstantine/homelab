resource "kubernetes_persistent_volume" "qbittorrent_config" {
  metadata {
    name = "arr-qbittorrent-config"
    labels = {
      type = "local"
      app  = "arr"
      use  = "qbittorrent-config"
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
        path = "/storage/arr/qbittorrent/config"
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

resource "kubernetes_persistent_volume_claim" "qbittorrent_config" {
  metadata {
    name      = "qbittorrent-config"
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
        use  = "qbittorrent-config"
      }
    }
  }
}

resource "kubernetes_service" "qbittorrent" {
  metadata {
    name      = "qbittorrent"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "qbittorrent"
    }
    port {
      name        = "webui"
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_stateful_set" "qbittorrent" {
  wait_for_rollout = false
  metadata {
    name      = "qbittorrent"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "qbittorrent"
      }
    }
    service_name = kubernetes_service.qbittorrent.metadata.0.name

    template {
      metadata {
        labels = {
          name = "qbittorrent"
        }
      }
      spec {
        container {
          name              = "qbittorrent"
          image             = "lscr.io/linuxserver/qbittorrent:latest"
          image_pull_policy = "Always"

          port {
            name           = "webui"
            container_port = 8080
          }
          port {
            name           = "torrent-tcp"
            container_port = 6881
            protocol       = "TCP"
          }
          port {
            name           = "torrent-udp"
            container_port = 6881
            protocol       = "UDP"
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
          env {
            name  = "WEBUI_PORT"
            value = "8080"
          }
          env {
            name  = "TORRENTING_PORT"
            value = "6881"
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.qbittorrent_config.metadata.0.name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.downloads.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "qbittorrent" {
  metadata {
    name      = "qbittorrent"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "qbittorrent.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.qbittorrent.metadata.0.name
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

resource "kubernetes_ingress_v1" "qbittorrent_tls" {
  metadata {
    name      = "qbittorrent-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "qbittorrent.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.qbittorrent.metadata.0.name
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

module "qbittorrent_dns" {
  source = "../pi-hole-service"

  record  = "qbittorrent.${var.domain}"
  ingress = kubernetes_ingress_v1.qbittorrent
}
