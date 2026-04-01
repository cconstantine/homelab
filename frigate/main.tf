resource "kubernetes_service" "frigate" {
  metadata {
    name      = "frigate"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "frigate"
    }
    port {
      port = 5000
    }
  }
}

resource "kubernetes_storage_class" "nfs" {
  metadata {
    name = "nfs-storage"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy      = "Retain"
  volume_binding_mode = "Immediate"
}

resource "kubernetes_persistent_volume" "frigate_nfs_media" {
  metadata {
    name = "frigate-media"
    labels = {
      type = "nfs"
      app  = "frigate"
      use  = "media"
    }
  }
  spec {
    capacity = {
      storage = "100Gi"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.nfs.metadata[0].name
    persistent_volume_source {
      nfs {
        server = "homelab.local"
        path   = "/storage/frigate/media"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}

resource "kubernetes_persistent_volume" "frigate_nfs_config" {
  metadata {
    name = "frigate-config"
    labels = {
      type = "nfs"
      app  = "frigate"
      use  = "config"
    }
  }
  spec {
    capacity = {
      storage = "1Gi"
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.nfs.metadata[0].name
    persistent_volume_source {
      nfs {
        server = "homelab.local"
        path   = "/storage/frigate/config"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
  }
}


resource "kubernetes_config_map" "config_yml" {
  metadata {
    name      = "frigate-config-yml-${sha1(file("${path.module}/config/config.yml"))}"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  data = {
    "config.yml" = "${file("${path.module}/config/config.yml")}"
  }
}

resource "kubernetes_stateful_set" "frigate" {
  wait_for_rollout = false
  metadata {
    name      = "frigate"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "frigate"
      }
    }
    service_name = kubernetes_service.frigate.metadata.0.name

    template {
      metadata {
        labels = {
          name = "frigate"
        }
      }
      spec {

        volume {
          name = "config-yml"
          config_map {
            name = kubernetes_config_map.config_yml.metadata.0.name
          }
        }

        volume {
          name = "tmp-cache"
          empty_dir {
            medium     = "Memory"
            size_limit = "1G"
          }
        }

        container {
          name  = "frigate"
          image = "ghcr.io/blakeblackshear/frigate:stable"
          env {
            name  = "FRIGATE_RTSP_PASSWORD"
            value = "password"
          }
          volume_mount {
            name       = "frigate-media"
            mount_path = "/media/frigate"
          }

          volume_mount {
            name       = "frigate-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "config-yml"
            mount_path = "/config/config.yml"
            sub_path   = "config.yml"
          }

          volume_mount {
            name       = "tmp-cache"
            mount_path = "/tmp/cache"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "frigate-config"
        labels = {
          type = "nfs"
          app  = "frigate"
          use  = "config"
        }
      }
      spec {
        access_modes       = ["ReadWriteMany"]
        storage_class_name = kubernetes_storage_class.nfs.metadata[0].name
        resources {
          requests = {
            storage = "1Gi"
          }
        }
        selector {
          match_labels = {
            type = "nfs"
            app  = "frigate"
            use  = "config"
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "frigate-media"
        labels = {
          type = "nfs"
          app  = "frigate"
          use  = "media"
        }
      }
      spec {
        access_modes       = ["ReadWriteMany"]
        storage_class_name = kubernetes_storage_class.nfs.metadata[0].name
        resources {
          requests = {
            storage = "100Gi"
          }
        }
        selector {
          match_labels = {
            type = "nfs"
            app  = "frigate"
            use  = "media"
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "frigate" {
  metadata {
    name      = "frigate"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "frigate.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.frigate.metadata.0.name
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}

module "frigate_dns" {
  source = "../pi-hole-service"

  record  = "frigate.${var.domain}"
  ingress = kubernetes_ingress_v1.frigate
}
