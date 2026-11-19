# Host-wide kernel settings, held on every node.
#
# These sysctls aren't namespaced, so pods can't set them through
# securityContext.sysctls; a privileged pod writes the host's value instead.
# The DaemonSet covers nodes as they join and re-applies after a reboot (the
# pod restarts with the node), with nothing to keep in /etc/sysctl.d per host.
#
# Each value is a floor: a node already set higher is left alone.
#
#   fs.aio-max-nr  Ceiling on in-flight async-IO requests across the host
#                  (default 65536). Workloads using io_setup/libaio (databases,
#                  storage engines, and every one of them nested under dind
#                  shares the host's count) hit it with EAGAIN. Raising it costs
#                  nothing until used.
locals {
  sysctls = {
    "fs.aio-max-nr" = 1048576
  }
}

resource "kubernetes_daemon_set_v1" "node_sysctls" {
  metadata {
    name      = "node-sysctls"
    namespace = "kube-system"
  }
  wait_for_rollout = false

  spec {
    selector {
      match_labels = {
        name = "node-sysctls"
      }
    }

    template {
      metadata {
        labels = {
          name = "node-sysctls"
        }
      }

      spec {
        priority_class_name = "system-node-critical"

        # Every node, the control plane and tainted GPU nodes included.
        toleration {
          operator = "Exists"
        }

        init_container {
          name  = "sysctls"
          image = "busybox:1.37.0"
          command = ["sh", "-c", join("\n", concat(
            ["set -eu"],
            [for k, v in local.sysctls : <<-EOT
              f=/proc/sys/${replace(k, ".", "/")}
              cur=$(cat "$f")
              if [ "$cur" -lt ${v} ]; then echo ${v} > "$f"; fi
              echo "${k} = $(cat "$f") (was $cur)"
            EOT
            ],
          ))]

          security_context {
            privileged = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              memory = "32Mi"
            }
          }
        }

        # Keeps the pod Running, so the init container reruns whenever the
        # node (or the pod) restarts.
        container {
          name  = "pause"
          image = "registry.k8s.io/pause:3.10"

          resources {
            requests = {
              cpu    = "1m"
              memory = "8Mi"
            }
            limits = {
              memory = "16Mi"
            }
          }
        }
      }
    }
  }
}
