locals {
  local_storage_class = "local-storage"
  storage_node        = "homelab"
}

resource "kubernetes_service" "jellyfin" {
  metadata {
    name      = "jellyfin"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "jellyfin"
    }
    port {
      port        = 8096
      target_port = 8096
    }
  }
}

# Note: the "local-storage" StorageClass is already created by the
# monitoring module (kubernetes.io/no-provisioner, WaitForFirstConsumer).
# It's a cluster-scoped object, so it's reused by name here rather than
# declared again.
#
# These are "local" volumes (not NFS): jellyfin now runs on homelab itself
# (see the node_selector below), so these paths are just plain directories
# on its own disk, bind-mounted in directly. Same underlying paths that
# used to be NFS-exported to jellyfin when it ran on ryzen - no data
# migration involved, just a different mount mechanism.

resource "kubernetes_persistent_volume" "jellyfin_config" {
  metadata {
    name = "jellyfin-config"
    labels = {
      type = "local"
      app  = "jellyfin"
      use  = "config"
    }
  }
  spec {
    capacity = {
      storage = "10Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/jellyfin/config"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.storage_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume" "jellyfin_movies" {
  metadata {
    name = "jellyfin-movies"
    labels = {
      type = "local"
      app  = "jellyfin"
      use  = "movies"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/jellyfin/media/movies"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.storage_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume" "jellyfin_tv" {
  metadata {
    name = "jellyfin-tv"
    labels = {
      type = "local"
      app  = "jellyfin"
      use  = "tv"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/jellyfin/media/tv"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.storage_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_stateful_set" "jellyfin" {
  wait_for_rollout = false
  metadata {
    name      = "jellyfin"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "jellyfin"
      }
    }
    service_name = kubernetes_service.jellyfin.metadata.0.name

    template {
      metadata {
        labels = {
          name = "jellyfin"
        }
      }
      spec {
        node_selector = {
          "nvidia.com/gpu.type"    = "discrete"
          "kubernetes.io/hostname" = local.storage_node
        }
        runtime_class_name = "nvidia"

        container {
          name              = "jellyfin"
          image             = "jellyfin/jellyfin:latest"
          image_pull_policy = "Always"

          port {
            container_port = 8096
          }

          env {
            name  = "TZ"
            value = "America/Los_Angeles"
          }
          env {
            name  = "NVIDIA_VISIBLE_DEVICES"
            value = "all"
          }
          env {
            name  = "NVIDIA_DRIVER_CAPABILITIES"
            value = "all"
          }

          resources {
            limits = {
              "nvidia.com/gpu" = "1"
            }
            requests = {
              "nvidia.com/gpu" = "1"
            }
          }

          volume_mount {
            name       = "jellyfin-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "jellyfin-cache"
            mount_path = "/cache"
          }

          volume_mount {
            name       = "jellyfin-movies"
            mount_path = "/media/movies"
          }

          volume_mount {
            name       = "jellyfin-tv"
            mount_path = "/media/tv"
          }
        }

        # Transcode cache is transient scratch space, not library data, so
        # it's kept local (ephemeral) rather than on the NFS volume.
        volume {
          name = "jellyfin-cache"
          empty_dir {}
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "jellyfin-config"
        labels = {
          type = "local"
          app  = "jellyfin"
          use  = "config"
        }
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = local.local_storage_class
        resources {
          requests = {
            storage = "10Gi"
          }
        }
        selector {
          match_labels = {
            type = "local"
            app  = "jellyfin"
            use  = "config"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "jellyfin-movies"
        labels = {
          type = "local"
          app  = "jellyfin"
          use  = "movies"
        }
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = local.local_storage_class
        resources {
          requests = {
            storage = "1Ti"
          }
        }
        selector {
          match_labels = {
            type = "local"
            app  = "jellyfin"
            use  = "movies"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "jellyfin-tv"
        labels = {
          type = "local"
          app  = "jellyfin"
          use  = "tv"
        }
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = local.local_storage_class
        resources {
          requests = {
            storage = "1Ti"
          }
        }
        selector {
          match_labels = {
            type = "local"
            app  = "jellyfin"
            use  = "tv"
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "jellyfin" {
  metadata {
    name      = "jellyfin"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "jellyfin.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.jellyfin.metadata.0.name
              port {
                number = 8096
              }
            }
          }
        }
      }
    }
  }
}

# Split from the .homelab ingress above so the redirect/HSTS middlewares
# (which force HTTPS) apply only to the public constantlee.us hostname -
# Traefik applies middleware annotations to the whole Ingress, not per rule.
resource "kubernetes_ingress_v1" "jellyfin_tls" {
  metadata {
    name      = "jellyfin-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "jellyfin.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.jellyfin.metadata.0.name
              port {
                number = 8096
              }
            }
          }
        }
      }
    }
  }
}

module "jellyfin_dns" {
  source = "../pi-hole-service"

  record  = "jellyfin.${var.domain}"
  ingress = kubernetes_ingress_v1.jellyfin
}
