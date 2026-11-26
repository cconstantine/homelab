# Host kernel settings: one DaemonSet per entry of local.node_sysctls, each
# on the nodes its selector picks ("all": every node).
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
#
# ryzen only (strata, ai/strata.tf):
#   vm.min_free_kbytes, vm.watermark_scale_factor  Start background reclaim
#                  well before RAM runs out (defaults 67584 / 10). Strata parks
#                  conversations as 2-4.6GB allocations next to a 56GiB pinned
#                  expert copy; with the defaults a park waited up to 107s on
#                  direct reclaim and the GPU's verify windows timed out.
#                  ai/strata.tf's --conversation-cache-min-free-mib assumes
#                  these. Set by hand once, lost on the 2026-11-18 reboot.
locals {
  node_sysctls = {
    all = {
      name          = "node-sysctls"
      node_selector = {}
      sysctls = {
        "fs.aio-max-nr" = 1048576
      }
    }
    ryzen = {
      name          = "node-sysctls-ryzen"
      node_selector = { "kubernetes.io/hostname" = "ryzen" }
      sysctls = {
        "vm.min_free_kbytes"        = 1048576
        "vm.watermark_scale_factor" = 100
      }
    }
  }
}

moved {
  from = kubernetes_daemon_set_v1.node_sysctls
  to   = kubernetes_daemon_set_v1.node_sysctls["all"]
}

resource "kubernetes_daemon_set_v1" "node_sysctls" {
  for_each = local.node_sysctls

  metadata {
    name      = each.value.name
    namespace = "kube-system"
  }
  wait_for_rollout = false

  spec {
    selector {
      match_labels = {
        name = each.value.name
      }
    }

    template {
      metadata {
        labels = {
          name = each.value.name
        }
      }

      spec {
        node_selector = each.value.node_selector

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
            [for k, v in each.value.sysctls : <<-EOT
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
