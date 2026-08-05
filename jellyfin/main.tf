locals {
  nfs_server        = "homelab.local"
  nfs_storage_class = "nfs-storage"
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

# Note: the "nfs-storage" StorageClass is already created by the frigate
# module (kubernetes.io/no-provisioner, Retain). It's a cluster-scoped
# object, so it's reused by name here rather than declared again.

resource "kubernetes_persistent_volume" "jellyfin_config" {
  metadata {
    name = "jellyfin-config"
    labels = {
      type = "nfs"
      app  = "jellyfin"
      use  = "config"
    }
  }
  spec {
    capacity = {
      storage = "10Gi"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    persistent_volume_source {
      nfs {
        server = local.nfs_server
        path   = "/storage/jellyfin/config"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}

resource "kubernetes_persistent_volume" "jellyfin_movies" {
  metadata {
    name = "jellyfin-movies"
    labels = {
      type = "nfs"
      app  = "jellyfin"
      use  = "movies"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    persistent_volume_source {
      nfs {
        server = local.nfs_server
        path   = "/storage/jellyfin/media/movies"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}

resource "kubernetes_persistent_volume" "jellyfin_tv" {
  metadata {
    name = "jellyfin-tv"
    labels = {
      type = "nfs"
      app  = "jellyfin"
      use  = "tv"
    }
  }
  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = local.nfs_storage_class
    persistent_volume_source {
      nfs {
        server = local.nfs_server
        path   = "/storage/jellyfin/media/tv"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
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
          "nvidia.com/gpu.type" = "discrete"
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
          type = "nfs"
          app  = "jellyfin"
          use  = "config"
        }
      }
      spec {
        access_modes       = ["ReadWriteMany"]
        storage_class_name = local.nfs_storage_class
        resources {
          requests = {
            storage = "10Gi"
          }
        }
        selector {
          match_labels = {
            type = "nfs"
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
          type = "nfs"
          app  = "jellyfin"
          use  = "movies"
        }
      }
      spec {
        access_modes       = ["ReadWriteMany"]
        storage_class_name = local.nfs_storage_class
        resources {
          requests = {
            storage = "1Ti"
          }
        }
        selector {
          match_labels = {
            type = "nfs"
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
          type = "nfs"
          app  = "jellyfin"
          use  = "tv"
        }
      }
      spec {
        access_modes       = ["ReadWriteMany"]
        storage_class_name = local.nfs_storage_class
        resources {
          requests = {
            storage = "1Ti"
          }
        }
        selector {
          match_labels = {
            type = "nfs"
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

module "jellyfin_dns" {
  source = "../pi-hole-service"

  record  = "jellyfin.${var.domain}"
  ingress = kubernetes_ingress_v1.jellyfin
}
