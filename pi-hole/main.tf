resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "kubernetes_stateful_set_v1" "pi_hole" {
  timeouts {
    create = "2m"
    delete = "2h"
  }
  metadata {
    name      = "pihole"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "pihole"
      }
    }
    service_name = kubernetes_service.pihole_dns.metadata.0.name

    template {
      metadata {
        labels = {
          name = "pihole"
        }
      }
      spec {
        container {
          name              = "pi-hole"
          image             = "pihole/pihole:latest"
          image_pull_policy = "IfNotPresent"
          env {
            name  = "WEBPASSWORD"
            value = random_password.password.result
          }
          volume_mount {
            name       = "etc-pihole"
            mount_path = "/etc/pihole/"
          }
          volume_mount {
            name       = "dnsmasq-pihole"
            mount_path = "/etc/dnsmasq.d/"
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "etc-pihole"
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
    volume_claim_template {
      metadata {
        name = "dnsmasq-pihole"
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

resource "kubernetes_service" "pihole_web" {
  metadata {
    name      = "pihole-web"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  spec {
    selector = {
      name = "pihole"
    }
    port {
      port = 80
    }
  }
}

resource "kubernetes_service" "pihole_api" {
  metadata {
    name      = "pihole-api"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  spec {
    selector = {
      name = "pihole"
    }
    type = "LoadBalancer"
    port {
      name     = "api"
      port     = 8080
      target_port = 80
    }
  }
}

resource "kubernetes_service" "pihole_dns" {
  metadata {
    name      = "pihole-dns"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  spec {
    external_traffic_policy = "Local"
    selector = {
      name = "pihole"
    }
    type = "LoadBalancer"
    port {
      name     = "dns"
      port     = 53
      protocol = "UDP"
    }
  }
}

resource "kubernetes_ingress_v1" "pihole_ingress" {
  metadata {
    name      = "pihole-ingress"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }

  spec {
    rule {
      host = var.fqdn
      http {
        path {
          backend {
            service {
              name = kubernetes_service.pihole_web.metadata.0.name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

  }
}
