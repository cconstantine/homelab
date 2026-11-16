resource "kubernetes_persistent_volume" "prowlarr_config" {
  metadata {
    name = "arr-prowlarr-config"
    labels = {
      type = "local"
      app  = "arr"
      use  = "prowlarr-config"
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
        path = "/storage/arr/prowlarr/config"
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

resource "kubernetes_persistent_volume_claim" "prowlarr_config" {
  metadata {
    name      = "prowlarr-config"
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
        use  = "prowlarr-config"
      }
    }
  }
}

# Prowlarr is the Longhorn trial (longhorn-plan.md, phase 2). Its data was
# copied here from prowlarr-config above, which is kept, unused, as the
# rollback: its PV is Retain and still points at /storage/arr/prowlarr/config.
resource "kubernetes_persistent_volume_claim" "prowlarr_config_longhorn" {
  metadata {
    name      = "prowlarr-config-longhorn"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn-r2"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_service" "prowlarr" {
  metadata {
    name      = "prowlarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "prowlarr"
    }
    port {
      port        = 9696
      target_port = 9696
    }
  }
}

resource "kubernetes_stateful_set" "prowlarr" {
  wait_for_rollout = false
  metadata {
    name      = "prowlarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "prowlarr"
      }
    }
    service_name = kubernetes_service.prowlarr.metadata.0.name

    template {
      metadata {
        labels = {
          name = "prowlarr"
        }
      }
      spec {
        # Nodes with Longhorn's CSI plugin, minus ryzen (Strata's memory)
        # and xavier-vm; see longhorn-storage/values.yaml.
        node_selector = {
          "homelab/longhorn-control" = "true"
        }

        container {
          name = "prowlarr"

          resources {
            requests = {
              cpu    = "10m"
              memory = "176Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }
          image             = "lscr.io/linuxserver/prowlarr:latest"
          image_pull_policy = "Always"

          port {
            container_port = 9696
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
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prowlarr_config_longhorn.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "prowlarr" {
  metadata {
    name      = "prowlarr"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "prowlarr.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.prowlarr.metadata.0.name
              port {
                number = 9696
              }
            }
          }
        }
      }
    }

  }
}

resource "kubernetes_ingress_v1" "prowlarr_tls" {
  metadata {
    name      = "prowlarr-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "prowlarr.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.prowlarr.metadata.0.name
              port {
                number = 9696
              }
            }
          }
        }
      }
    }
  }
}

module "prowlarr_dns" {
  source = "../pi-hole-service"

  record  = "prowlarr.${var.domain}"
  ingress = kubernetes_ingress_v1.prowlarr
}
