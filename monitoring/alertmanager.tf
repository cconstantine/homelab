# Alertmanager (SME-903): receives Prometheus's alerts (config/prometheus.yml
# alerting: block).
#
# Silences and the notification log live on a longhorn-r2 PVC -- 2 replicas
# with best-effort data locality, so the volume follows the pod between nodes.
# Silences are how On-call acknowledges an alert, so they must survive a
# restart; prometheus.tf's own local-storage data PVC stays node-pinned.
#
# No nodeSelector: the user's call, 2026-11-28 (SME-903) -- "let it place
# wherever it wants". The ryzen taint (dedicated=strata) and xavier-vm's
# firecracker preference keep it off those two on their own; if landing on
# framework (the laptop) ever bites, a homelab/longhorn-control selector is
# one line (trade-off 3).
#
# No ingress and no pi-hole record: the v2 API is unauthenticated, so it
# stays pod-network (trade-off 4). Readers are in-cluster -- Prometheus
# alerts here now, On-call's alert-wait later.

resource "kubernetes_persistent_volume_claim" "alertmanager_data" {
  metadata {
    name      = "alertmanager-data"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn-r2" # the movable app class, see longhorn-storage/
    resources {
      requests = {
        storage = "1Gi" # generous for silences + notification log
      }
    }
  }
}

# The name-embeds-sha1 pattern (prometheus.tf): editing the routing config
# changes the ConfigMap name, which re-creates the pod -- and the new pod
# loads silences back off the volume. The --storage.path/config split is what
# makes a routing edit silence-safe.
resource "kubernetes_config_map" "alertmanager_yml" {
  metadata {
    name      = "alertmanager-yml-${sha1(file("${path.module}/config/alertmanager.yml"))}"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "alertmanager.yml" = "${file("${path.module}/config/alertmanager.yml")}"
  }
}

resource "kubernetes_deployment" "alertmanager" {
  wait_for_rollout = false
  metadata {
    name      = "alertmanager"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    replicas = 1
    # Recreate: the data PVC is RWO, so a RollingUpdate's new pod could never
    # attach while the old pod holds it, and the rollout would hang.
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "alertmanager"
      }
    }
    template {
      metadata {
        labels = {
          name = "alertmanager"
        }
      }
      spec {
        # Longhorn formats a fresh ext4 root-owned; the image runs as nobody
        # (uid 65534). Same shape as prometheus.tf's init-chown-data.
        init_container {
          name              = "init-chown-data"
          image             = "busybox:1.37.0"
          image_pull_policy = "IfNotPresent"
          command           = ["chown", "-R", "65534:65534", "/alertmanager"]

          volume_mount {
            name       = "alertmanager-data"
            mount_path = "/alertmanager"
          }
        }

        container {
          name = "alertmanager"
          # Pinned, not :latest: v0.35.1's single fix (#5744) raises the HTTP
          # idle timeout above Prometheus's 5m notify timeout -- this exact
          # integration.
          image = "prom/alertmanager:v0.35.1"

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager"
          ]

          volume_mount {
            name       = "alertmanager-yml"
            mount_path = "/etc/alertmanager"
          }

          volume_mount {
            name       = "alertmanager-data"
            mount_path = "/alertmanager"
          }

          readiness_probe {
            http_get {
              path = "/-/healthy"
              port = 9093
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = 9093
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 2
            failure_threshold     = 6
          }

          resources {
            requests = {
              cpu    = "5m"
              memory = "64Mi"
            }
            limits = {
              memory = "192Mi"
            }
          }
        }

        volume {
          name = "alertmanager-yml"
          config_map {
            name = kubernetes_config_map.alertmanager_yml.metadata.0.name
          }
        }
        volume {
          name = "alertmanager-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.alertmanager_data.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    selector = {
      name = "alertmanager"
    }
    port {
      port = 9093
    }
  }
}
