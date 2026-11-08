resource "kubernetes_labels" "homelab_gpu" {
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = "homelab"
  }
  labels = {
    "nvidia.com/gpu.present" = "true"
    "nvidia.com/gpu.type"    = "discrete"
  }
}

resource "kubernetes_runtime_class_v1" "nvidia" {
  metadata {
    name = "nvidia"
  }
  handler = "nvidia"
}

resource "kubernetes_config_map" "discrete_device_plugin_config" {
  metadata {
    name      = "discrete-device-plugin-config"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  data = {
    "config.yaml" = <<-EOF
      version: v1
      sharing:
        timeSlicing:
          resources:
          - name: nvidia.com/gpu
            replicas: 2
    EOF
  }
}

resource "kubernetes_daemonset" "nvidia_device_plugin_discrete" {
  metadata {
    name      = "nvidia-device-plugin-discrete"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  wait_for_rollout = false

  spec {
    selector {
      match_labels = {
        name = "nvidia-device-plugin-discrete"
      }
    }

    template {
      metadata {
        labels = {
          name = "nvidia-device-plugin-discrete"
        }
      }

      spec {
        node_selector = {
          "nvidia.com/gpu.type" = "discrete"
        }

        runtime_class_name = "nvidia"

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {
          name = "nvidia-device-plugin"

          resources {
            requests = {
              cpu    = "10m"
              memory = "48Mi"
            }
            limits = {
              memory = "64Mi"
            }
          }
          image = "nvcr.io/nvidia/k8s-device-plugin:v0.14.5"
          args  = ["--config-file", "/config/config.yaml"]

          security_context {
            privileged = true
          }

          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }

          volume_mount {
            name       = "plugin-config"
            mount_path = "/config"
            read_only  = true
          }
        }

        volume {
          name = "device-plugin"
          host_path {
            path = "/var/lib/kubelet/device-plugins"
          }
        }

        volume {
          name = "plugin-config"
          config_map {
            name = kubernetes_config_map.discrete_device_plugin_config.metadata.0.name
          }
        }
      }
    }
  }
}
