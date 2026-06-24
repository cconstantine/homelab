resource "kubernetes_labels" "xavier_gpu" {
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = "xavier"
  }
  labels = {
    "nvidia.com/gpu.present" = "true"
    "nvidia.com/gpu.type"    = "tegra"
  }
}

resource "kubernetes_labels" "ryzen_gpu" {
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = "ryzen"
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

# JetPack 4.x kernel (4.9.201-tegra) doesn't expose /sys/devices/soc0/family,
# which the device plugin uses to detect Tegra. This ConfigMap fakes it.
resource "kubernetes_config_map" "tegra_soc0" {
  metadata {
    name      = "tegra-soc0"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  data = {
    "family" = "Tegra\n"
  }
}

resource "kubernetes_daemonset" "nvidia_device_plugin_tegra" {
  metadata {
    name      = "nvidia-device-plugin-tegra"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  wait_for_rollout = false

  spec {
    selector {
      match_labels = {
        name = "nvidia-device-plugin-tegra"
      }
    }

    template {
      metadata {
        labels = {
          name = "nvidia-device-plugin-tegra"
        }
      }

      spec {
        node_selector = {
          "nvidia.com/gpu.type" = "tegra"
        }

        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {
          name  = "nvidia-device-plugin"
          image = "nvcr.io/nvidia/k8s-device-plugin:v0.14.5"

          security_context {
            privileged = true
          }

          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }

          volume_mount {
            name       = "tegra-soc0"
            mount_path = "/sys/devices/soc0"
            read_only  = true
          }

          volume_mount {
            name       = "nvidia-csv"
            mount_path = "/etc/nvidia-container-runtime/host-files-for-container.d"
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
          name = "tegra-soc0"
          config_map {
            name = kubernetes_config_map.tegra_soc0.metadata.0.name
          }
        }

        volume {
          name = "nvidia-csv"
          host_path {
            path = "/etc/nvidia-container-runtime/host-files-for-container.d"
          }
        }
      }
    }
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
          name  = "nvidia-device-plugin"
          image = "nvcr.io/nvidia/k8s-device-plugin:v0.14.5"

          security_context {
            privileged = true
          }

          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }
        }

        volume {
          name = "device-plugin"
          host_path {
            path = "/var/lib/kubelet/device-plugins"
          }
        }
      }
    }
  }
}
