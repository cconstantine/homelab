resource "kubernetes_labels" "ryzen_gpu" {
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = "ryzen"
  }
  labels = {
    "amd.com/gpu.present" = "true"
    "amd.com/gpu.type"    = "r9700"
  }
}

# ryzen has two amdgpu devices: the Radeon AI PRO R9700 (03:00.0, gfx1201,
# 32GB) and the Raphael iGPU (6e:00.0, gfx1036). Both show up as KFD nodes,
# so ROCm's own k8s-device-plugin would advertise 2x amd.com/gpu and could
# hand a pod the iGPU. Instead, use generic-device-plugin to expose exactly
# the R9700's render node (plus the shared /dev/kfd) as amd.com/r9700. ROCm
# and Vulkan both only enumerate render nodes they can see, so pods get the
# R9700 and nothing else.
#
# renderD128 <-> 03:00.0 per /dev/dri/by-path. Paths are the real nodes, not
# the by-path symlinks, since containerd won't create devices from symlinks.
# If PCI enumeration order ever changes, re-check by-path and update this.
#
# count = 2 mirrors the old nvidia time-slicing (replicas: 2) so
# llama-cpp-ryzen and ollama-ryzen can both claim a slot. Like time-slicing,
# this shares compute but not VRAM.
resource "kubernetes_daemonset" "r9700_device_plugin" {
  metadata {
    name      = "r9700-device-plugin"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  wait_for_rollout = false

  spec {
    selector {
      match_labels = {
        name = "r9700-device-plugin"
      }
    }

    template {
      metadata {
        labels = {
          name = "r9700-device-plugin"
        }
      }

      spec {
        priority_class_name = "system-node-critical"

        node_selector = {
          "amd.com/gpu.type" = "r9700"
        }

        # Disable runtime PM on the R9700. When idle, amdgpu runtime-suspends
        # the headless card and evicts all VRAM to GTT (system RAM) --
        # observed: 57MiB VRAM / 47GB GTT with llama-cpp-ryzen loaded --
        # then has to migrate it back on the next request. It also makes
        # gpu_busy_percent/hwmon reads fail with EBUSY, so no metrics.
        # Not persistent across reboots on its own; this re-applies it
        # whenever the pod starts.
        init_container {
          name    = "disable-runtime-pm"
          image   = "busybox:1.37"
          command = ["sh", "-c", "echo on > /host-sys/bus/pci/devices/0000:03:00.0/power/control"]

          security_context {
            privileged = true
          }

          volume_mount {
            name       = "sys"
            mount_path = "/host-sys"
          }
        }

        container {
          name  = "generic-device-plugin"
          image = "squat/generic-device-plugin:2cc50b0"
          args = [
            "--domain", "amd.com",
            "--device", <<-EOF
              name: r9700
              groups:
                - count: 2
                  paths:
                    - path: /dev/kfd
                    - path: /dev/dri/renderD128
            EOF
          ]

          security_context {
            privileged = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "10Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "20Mi"
            }
          }

          volume_mount {
            name       = "device-plugin"
            mount_path = "/var/lib/kubelet/device-plugins"
          }

          volume_mount {
            name       = "dev"
            mount_path = "/dev"
          }
        }

        volume {
          name = "device-plugin"
          host_path {
            path = "/var/lib/kubelet/device-plugins"
          }
        }

        volume {
          name = "dev"
          host_path {
            path = "/dev"
          }
        }

        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
      }
    }
  }
}
