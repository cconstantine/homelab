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

resource "kubernetes_ingress_v1" "ollama_tls" {
  metadata {
    name      = "ollama-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "ollama.${var.tls_domain}"
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

# resource "kubernetes_stateful_set_v1" "ollama" {
#   wait_for_rollout = false
#   metadata {
#     name      = "ollama"
#     namespace = kubernetes_namespace.namespace.metadata.0.name
#   }
#   spec {
#     replicas     = 1
#     service_name = kubernetes_service_v1.ollama.metadata.0.name
#     selector {
#       match_labels = {
#         name = "ollama"
#       }
#     }

#     template {
#       metadata {
#         labels = {
#           name = "ollama"
#         }
#       }
#       spec {
#         node_selector = {
#           "nvidia.com/gpu.type" = "tegra"
#         }

#         runtime_class_name = "nvidia"
#         host_network       = true

#         init_container {
#           name    = "init-storage"
#           image   = "busybox"
#           command = ["sh", "-c", "mkdir -p /host/var/lib/rancher/ollama/models"]
#           security_context {
#             privileged = true
#           }
#           volume_mount {
#             name       = "host-root"
#             mount_path = "/host"
#           }
#         }

#         container {
#           name  = "ollama"
#           image = "ollama/ollama"

#           port {
#             container_port = 11434
#           }

#           env {
#             name  = "NVIDIA_VISIBLE_DEVICES"
#             value = "all"
#           }
#           env {
#             name  = "NVIDIA_DRIVER_CAPABILITIES"
#             value = "all"
#           }
#           env {
#             name  = "OLLAMA_HOST"
#             value = "0.0.0.0"
#           }
#           env {
#             name  = "JETSON_JETPACK"
#             value = "5"
#           }
#           env {
#             name  = "OLLAMA_FLASH_ATTENTION"
#             value = "1"
#           }
#           env {
#             name  = "OLLAMA_KV_CACHE_TYPE"
#             value = "q4_0"
#           }

#           volume_mount {
#             name       = "ollama-models"
#             mount_path = "/root/.ollama"
#           }
#         }

#         volume {
#           name = "host-root"
#           host_path {
#             path = "/"
#           }
#         }

#         volume {
#           name = "ollama-models"
#           host_path {
#             path = "/var/lib/rancher/ollama/models"
#           }
#         }
#       }
#     }
#   }
# }

resource "kubernetes_config_map" "ollama_exporter_script" {
  metadata {
    name      = "ollama-exporter-script"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  data = {
    "exporter.py" = file("${path.module}/ollama_exporter.py")
  }
}

resource "kubernetes_ingress_v1" "ollama_ryzen" {
  metadata {
    name      = "ollama-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "ollama-ryzen.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.ollama_ryzen.metadata.0.name
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

resource "kubernetes_ingress_v1" "ollama_ryzen_tls" {
  metadata {
    name      = "ollama-ryzen-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "ollama-ryzen.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.ollama_ryzen.metadata.0.name
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

resource "kubernetes_service_v1" "ollama_ryzen" {
  metadata {
    name      = "ollama-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "ollama-ryzen"
    }
    port {
      port        = 11434
      target_port = 11434
    }
  }
}

resource "kubernetes_ingress_v1" "ollama_xavier" {
  metadata {
    name      = "ollama-xavier"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "ollama-xavier.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.ollama_xavier.metadata.0.name
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

resource "kubernetes_ingress_v1" "ollama_xavier_tls" {
  metadata {
    name      = "ollama-xavier-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "ollama-xavier.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.ollama_xavier.metadata.0.name
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

resource "kubernetes_service_v1" "ollama_xavier" {
  metadata {
    name      = "ollama-xavier"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "ollama-xavier"
    }
    port {
      port        = 11434
      target_port = 11434
    }
  }
}

resource "kubernetes_deployment_v1" "ollama_xavier" {
  wait_for_rollout = false
  metadata {
    name      = "ollama-xavier"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "ollama-xavier"
      }
    }

    template {
      metadata {
        labels = {
          name = "ollama-xavier"
        }
        annotations = {
          prometheus_io_scrape = "true"
          prometheus_io_port   = "11434"
        }
      }
      spec {
        node_selector = {
          "nvidia.com/gpu.type" = "tegra"
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

        init_container {
          name  = "init-exporter-packages"
          image = "python:3.11-slim"
          command = ["pip", "install", "--target=/packages", "--no-cache-dir", "--quiet",
          "fastapi", "uvicorn", "httpx", "prometheus_client"]
          volume_mount {
            name       = "exporter-packages"
            mount_path = "/packages"
          }
        }

        container {
          name    = "ollama"
          image   = "ollama/ollama"
          command = ["ollama", "serve"]

          port {
            container_port = 11435
          }

          env {
            name  = "JETSON_JETPACK"
            value = "5"
          }
          env {
            name  = "LD_LIBRARY_PATH"
            value = "/usr/lib/ollama:/usr/lib/ollama/cuda_jetpack5"
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
            value = "0.0.0.0:11435"
          }
          env {
            name  = "OLLAMA_NUM_GPU"
            value = "999"
          }
          env {
            name  = "OLLAMA_FLASH_ATTENTION"
            value = "1"
          }
          env {
            name  = "OLLAMA_KV_CACHE_TYPE"
            value = "q8_0"
          }
          env {
            name  = "OLLAMA_NUM_THREAD"
            value = "8"
          }
          env {
            name  = "OLLAMA_NUM_PARALLEL"
            value = "1"
          }
          env {
            name  = "OLLAMA_MAX_LOADED_MODELS"
            value = "1"
          }

          resources {
            requests = {
              cpu              = "10m"
              memory           = "32Mi"
              "nvidia.com/gpu" = "1"
            }
            limits = {
              "nvidia.com/gpu" = "1"
            }
          }

          volume_mount {
            name       = "ollama-models"
            mount_path = "/root/.ollama"
          }
        }

        container {
          name = "ollama-metrics"

          resources {
            requests = {
              cpu    = "10m"
              memory = "48Mi"
            }
            limits = {
              memory = "80Mi"
            }
          }
          image   = "python:3.11-slim"
          command = ["python3", "/exporter/exporter.py"]

          port {
            container_port = 11434
          }

          env {
            name  = "OLLAMA_HOST"
            value = "http://localhost:11435"
          }

          env {
            name  = "PORT"
            value = "11434"
          }

          env {
            name  = "PYTHONPATH"
            value = "/packages"
          }

          volume_mount {
            name       = "exporter-packages"
            mount_path = "/packages"
          }

          volume_mount {
            name       = "exporter-script"
            mount_path = "/exporter"
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

        volume {
          name = "exporter-packages"
          empty_dir {}
        }

        volume {
          name = "exporter-script"
          config_map {
            name = kubernetes_config_map.ollama_exporter_script.metadata.0.name
          }
        }

      }
    }
  }
}

resource "kubernetes_deployment_v1" "ollama_ryzen" {
  wait_for_rollout = false
  metadata {
    name      = "ollama-ryzen"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    # Runs alongside kubernetes_deployment_v1.llama_cpp_ryzen by sharing
    # the R9700 (amd-device-plugin advertises amd.com/r9700 with count: 2)
    # -- both claim 1 of the 2 slots on ryzen's single physical GPU. Time-slicing shares compute but not VRAM,
    # so watch for OOM if both load large models concurrently. Scaled to 0
    # while llama-cpp-ryzen runs Qwen3.8-Flash-Next (needs most of the 3070's
    # 8GB VRAM for attention/KV).
    replicas = 0
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "ollama-ryzen"
      }
    }

    template {
      metadata {
        labels = {
          name = "ollama-ryzen"
        }
        annotations = {
          prometheus_io_scrape = "true"
          prometheus_io_port   = "11434"
        }
      }
      spec {
        node_selector = {
          "amd.com/gpu.type"       = "r9700"
          "kubernetes.io/hostname" = "ryzen"
        }

        # ryzen is tainted dedicated=strata (amd-device-plugin/main.tf).
        toleration {
          key      = "dedicated"
          operator = "Equal"
          value    = "strata"
          effect   = "NoSchedule"
        }

        host_network = true

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

        init_container {
          name  = "init-exporter-packages"
          image = "python:3.11-slim"
          command = ["pip", "install", "--target=/packages", "--no-cache-dir", "--quiet",
          "fastapi", "uvicorn", "httpx", "prometheus_client"]
          volume_mount {
            name       = "exporter-packages"
            mount_path = "/packages"
          }
        }

        container {
          name  = "ollama"
          image = "ollama/ollama:rocm"

          port {
            container_port = 11435
          }

          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0:11435"
          }
          env {
            name  = "OLLAMA_NUM_GPU"
            value = "999"
          }
          env {
            name  = "OLLAMA_FLASH_ATTENTION"
            value = "1"
          }
          env {
            name  = "OLLAMA_KV_CACHE_TYPE"
            value = "q8_0"
          }
          env {
            name  = "OLLAMA_NUM_THREAD"
            value = "32"
          }
          env {
            name  = "OLLAMA_NUM_PARALLEL"
            value = "1"
          }
          env {
            name  = "OLLAMA_MAX_LOADED_MODELS"
            value = "1"
          }

          resources {
            limits = {
              "amd.com/r9700" = "1"
            }
            requests = {
              "amd.com/r9700" = "1"
            }
          }

          volume_mount {
            name       = "ollama-models"
            mount_path = "/root/.ollama"
          }
        }

        container {
          name    = "ollama-metrics"
          image   = "python:3.11-slim"
          command = ["python3", "/exporter/exporter.py"]

          port {
            container_port = 11434
          }

          env {
            name  = "OLLAMA_HOST"
            value = "http://localhost:11435"
          }

          env {
            name  = "PORT"
            value = "11434"
          }

          env {
            name  = "PYTHONPATH"
            value = "/packages"
          }

          volume_mount {
            name       = "exporter-packages"
            mount_path = "/packages"
          }

          volume_mount {
            name       = "exporter-script"
            mount_path = "/exporter"
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

        volume {
          name = "exporter-packages"
          empty_dir {}
        }

        volume {
          name = "exporter-script"
          config_map {
            name = kubernetes_config_map.ollama_exporter_script.metadata.0.name
          }
        }
      }
    }
  }
}
