resource "kubernetes_service" "chat" {
  metadata {
    name      = "chat"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "chat"
    }
    port {
      port = 8080
    }
  }
}

resource "kubernetes_persistent_volume" "chat_data" {
  metadata {
    name = "chat-data"
    labels = {
      type = "local"
      app  = "chat"
    }
  }
  spec {
    capacity = {
      storage = "100Gi"
    }
    access_modes = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = "local-storage"
    persistent_volume_source {
      local {
        path = "/storage/chat/data"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key = "kubernetes.io/hostname"
            operator = "In"
            values = ["homelab"]
          }
        }
      }
    }

  }
}

resource "kubernetes_stateful_set" "chat" {
  wait_for_rollout = false
  metadata {
    name      = "chat"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "chat"
      }
    }
    service_name = kubernetes_service.chat.metadata.0.name

    template {
      metadata {
        labels = {
          name = "chat"
        }
      }
      spec {
        container {
          name  = "chat"
          image = "ghcr.io/open-webui/open-webui:main"
          env {
            name = "OLLAMA_BASE_URL"
            value = "http://192.168.8.217:11434"
          }
          volume_mount {
            name       = "chat-data"
            mount_path = "/app/backend/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "chat-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        storage_class_name = "local-storage"
        resources {
          requests = {
            storage = "100Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "chat" {
  metadata {
    name      = "chat"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "chat.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.chat.metadata.0.name
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

module "chat_dns" {
  source   = "../pi-hole-service"

  record  = "chat.${var.domain}"
  ingress = kubernetes_ingress_v1.chat
}
