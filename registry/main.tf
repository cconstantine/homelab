locals {
  local_storage_class = "local-storage"
  storage_node        = "homelab"
}

resource "kubernetes_service" "registry" {
  metadata {
    name      = "registry"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "registry"
    }
    port {
      port        = 5000
      target_port = 5000
    }
  }
}

resource "kubernetes_persistent_volume" "registry_data" {
  metadata {
    name = "registry-data"
    labels = {
      type = "local"
      app  = "registry"
      use  = "data"
    }
  }
  spec {
    capacity = {
      storage = "200Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/registry/data"
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

resource "kubernetes_stateful_set" "registry" {
  wait_for_rollout = false
  metadata {
    name      = "registry"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "registry"
      }
    }
    service_name = kubernetes_service.registry.metadata.0.name

    template {
      metadata {
        labels = {
          name = "registry"
        }
      }
      spec {
        container {
          name              = "registry"
          image             = "registry:2"
          image_pull_policy = "Always"

          port {
            container_port = 5000
          }

          env {
            name  = "REGISTRY_STORAGE_DELETE_ENABLED"
            value = "true"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "registry-data"
            mount_path = "/var/lib/registry"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "registry-data"
        labels = {
          type = "local"
          app  = "registry"
          use  = "data"
        }
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = local.local_storage_class
        resources {
          requests = {
            storage = "200Gi"
          }
        }
        selector {
          match_labels = {
            type = "local"
            app  = "registry"
            use  = "data"
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "registry_tls" {
  metadata {
    name      = "registry-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "cr.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.registry.metadata.0.name
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
