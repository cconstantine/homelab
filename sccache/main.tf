# Shared sccache cache for smelt's CI: a WebDAV server (rclone) on a Longhorn
# volume. Builds reach it at
#   SCCACHE_WEBDAV_ENDPOINT=http://sccache.sccache.svc.cluster.local:8080/
# with RUSTC_WRAPPER=sccache; that part lives in smelt's CI, not here.
#
# Only the ARC runner pods can reach it (NetworkPolicy below): a cache anyone
# can write to lets them plant build outputs that CI then links in, and
# smelt-park's sandboxes share this cluster.
#
# One replica, Recreate: the volume is ReadWriteOnce, so only one node can
# mount it, and a rolling update would leave the new pod waiting on the old.

locals {
  name  = "sccache"
  port  = 8080
  image = "rclone/rclone:1.76.0"

  # Volume size, and the size the trimmer cuts the cache back to. sccache
  # never deletes from a remote cache, so without the trimmer it fills the
  # volume. Longhorn books the full volume size on both replica nodes.
  volume_size = "50Gi"
  trim_to_kib = 40 * 1024 * 1024

  labels = { name = local.name }
}

resource "kubernetes_persistent_volume_claim" "cache" {
  metadata {
    name      = "${local.name}-data"
    namespace = kubernetes_namespace.sccache.metadata.0.name
  }
  spec {
    # Two replicas, best-effort locality (longhorn-storage/main.tf): if the
    # node dies the pod restarts elsewhere with the cache intact, and a
    # replica follows the pod so reads are local.
    storage_class_name = "longhorn-r2"
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.volume_size
      }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_deployment" "sccache" {
  wait_for_rollout = false
  metadata {
    name      = local.name
    namespace = kubernetes_namespace.sccache.metadata.0.name
    labels    = local.labels
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = local.labels
    }
    template {
      metadata {
        labels = local.labels
      }
      spec {
        affinity {
          node_affinity {
            # A node with a Longhorn disk, so a replica can sit next to the pod.
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "node.longhorn.io/create-default-disk"
                  operator = "Exists"
                }
              }
            }
            # cachyos-x8664: NVMe and 2.5G. homelab next: 10G, but its Longhorn
            # disk is the SATA SSD the rest of k3s already keeps busy.
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              preference {
                match_expressions {
                  key      = "kubernetes.io/hostname"
                  operator = "In"
                  values   = ["cachyos-x8664"]
                }
              }
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 50
              preference {
                match_expressions {
                  key      = "kubernetes.io/hostname"
                  operator = "In"
                  values   = ["homelab"]
                }
              }
            }
          }
        }

        container {
          name  = "webdav"
          image = local.image
          args = [
            "serve", "webdav", "/data",
            "--addr", ":${local.port}",
            "--config", "/dev/null",
          ]
          port {
            name           = "webdav"
            container_port = local.port
          }
          readiness_probe {
            tcp_socket {
              port = local.port
            }
            period_seconds = 10
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        # Hourly: if the cache is over the target, delete the least recently
        # read files until it's back under. Reads set atime (relatime: at most
        # once a day per file), so this is LRU at day granularity. Cache keys
        # are hex hashes, so file names have no spaces. Empty directories are
        # left alone: removing one could race a build's MKCOL-then-PUT.
        container {
          name    = "trim"
          image   = local.image
          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            set -u
            while true; do
              used=$(du -sk /data | cut -f1)
              if [ "$used" -gt ${local.trim_to_kib} ]; then
                need=$(( (used - ${local.trim_to_kib}) * 1024 ))
                find /data -type f -exec stat -c '%X %s %n' {} + | sort -n \
                  | awk -v need="$need" '{ if (freed >= need) exit; freed += $2; print $3 }' \
                  | xargs -r rm -f
                echo "trim: was $${used}KiB, now $(du -sk /data | cut -f1)KiB"
              fi
              sleep 3600
            done
          EOT
          ]
          resources {
            requests = {
              cpu    = "5m"
              memory = "16Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.cache.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "sccache" {
  metadata {
    name      = local.name
    namespace = kubernetes_namespace.sccache.metadata.0.name
  }
  spec {
    selector = local.labels
    port {
      name        = "webdav"
      port        = local.port
      target_port = local.port
    }
  }
}

# k3s enforces NetworkPolicies. Builds run in containers inside the runner
# pod's own dockerd, whose traffic leaves with the runner pod's IP, so this
# admits them too.
resource "kubernetes_network_policy" "sccache" {
  metadata {
    name      = local.name
    namespace = kubernetes_namespace.sccache.metadata.0.name
  }
  spec {
    pod_selector {
      match_labels = local.labels
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "arc-runners" }
        }
      }
      ports {
        port     = local.port
        protocol = "TCP"
      }
    }
  }
}
