resource "kubernetes_ingress_v1" "ollama" {
  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "ollama.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.ollama.metadata.0.name
              port {
                number = 11434
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ollama" {
  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "ollama"
    }
    port {
      port        = 11434
      target_port = 11434
    }
  }
}

resource "kubernetes_stateful_set_v1" "ollama" {
  wait_for_rollout = false
  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.ollama.metadata.0.name
    selector {
      match_labels = {
        name = "ollama"
      }
    }

    template {
      metadata {
        labels = {
          name = "ollama"
        }
      }
      spec {
        node_selector = {
          "kubernetes.io/hostname" = "xavier"
        }

        runtime_class_name = "nvidia"
        host_network       = true

        init_container {
          name    = "init-storage"
          image   = "busybox"
          command = ["sh", "-c", "mkdir -p /host/var/lib/rancher/ollama/models"]
          security_context {
            privileged = true
          }
          volume_mount {
            name       = "host-root"
            mount_path = "/host"
          }
        }

        container {
          name  = "ollama"
          image = "ollama/ollama"

          port {
            container_port = 11434
          }

          env {
            name  = "NVIDIA_VISIBLE_DEVICES"
            value = "all"
          }
          env {
            name  = "NVIDIA_DRIVER_CAPABILITIES"
            value = "all"
          }
          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0"
          }
          env {
            name  = "JETSON_JETPACK"
            value = "5"
          }

          volume_mount {
            name       = "ollama-models"
            mount_path = "/root/.ollama"
          }
        }

        volume {
          name = "host-root"
          host_path {
            path = "/"
          }
        }

        volume {
          name = "ollama-models"
          host_path {
            path = "/var/lib/rancher/ollama/models"
          }
        }
      }
    }
  }
}
