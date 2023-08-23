
resource "kubernetes_stateful_set_v1" "wireguard" {
  timeouts {
    create = "2m"
    delete = "2h"
  }
  metadata {
    name      = "wireguard"
    namespace = kubernetes_namespace.wireguard.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "wireguard"
      }
    }
    service_name = kubernetes_service.wireguard_udp.metadata.0.name

    template {
      metadata {
        labels = {
          name = "wireguard"
        }
      }
      spec {
        container {
          name              = "wireguard"
          image             = "lscr.io/linuxserver/wireguard:latest"
          image_pull_policy = "IfNotPresent"
          security_context {
             capabilities {
               add = ["NET_ADMIN", "SYS_MODULE"]
             }
            #  sysctl {
            #     name = "net.ipv4.conf.all.src_valid_mark"
            #     value = "1"
            #  }
          }
          env {
            name  = "TZ"
            value = "Etc/UTC"
          }
          env {
            name  = "SERVERURL"
            value = "sillypants.ddns.net"
          }
          env {
            name  = "PEERS"
            value = "1"
          }
          volume_mount {
            name       = "modules"
            mount_path = "/lib/modules"
          }
        }
        volume {
            name = "modules"
            host_path {
                path = "/lib/modules"
                type = "Directory"
            }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "config"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "wireguard_udp" {
  metadata {
    name      = "wireguard-udp"
    namespace = kubernetes_namespace.wireguard.metadata.0.name
  }
  spec {
    external_traffic_policy = "Local"
    selector = {
      name = "wireguard"
    }
    type = "LoadBalancer"
    port {
      name     = "wireguard-udp"
      port     = 51820
      protocol = "UDP"
    }
  }
}
