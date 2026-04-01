resource "kubernetes_daemonset" "node_exporter" {
  metadata {
    name      = "node-exporter"
    namespace = kubernetes_namespace.monitoring.metadata.0.name

  }
  wait_for_rollout = false
  spec {
    selector {
      match_labels = {
        name = "node-exporter"
      }
    }
    template {
      metadata {
        labels = {
          name = "node-exporter"
        }
        annotations = {
          prometheus_io_scrape = true
        }
      }
      spec {
        host_network = true
        host_pid     = true
        container {
          name  = "node-exporter"
          image = "prom/node-exporter:v1.8.2"
          port {
            container_port = 9100
            protocol       = "TCP"
          }

          args = [
            "--path.sysfs=/host/sys",
            "--path.rootfs=/host/root",
            "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)",
            # "--collector.filesystem.ignored-mount-points=^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/pods/.+)($|/)",
            "--collector.netclass.ignored-devices=^(veth.*)$",
            "--no-collector.thermal_zone"
          ]
          volume_mount {
            name              = "sys"
            mount_path        = "/host/sys"
            mount_propagation = "HostToContainer"
            read_only         = true
          }

          volume_mount {
            name              = "root"
            mount_path        = "/host/root"
            mount_propagation = "HostToContainer"
            read_only         = true
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
        volume {
          name = "root"
          host_path {
            path = "/"
          }
        }
      }
    }
  }
}
