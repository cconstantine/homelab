resource "kubernetes_namespace" "pi_hole" {
  metadata {
    name = "pi-hole"
  }
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "kubernetes_persistent_volume_claim" "etc_pihole" {
  metadata {
    name      = "etc-pihole"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "local-path"
  }
}

resource "kubernetes_persistent_volume_claim" "dnsmasq_pihole" {
  metadata {
    name      = "dnsmasq-pihole"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "local-path"
  }
}


resource "kubernetes_stateful_set" "pi_hole" {
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
        volume {
          name = "etc-pihole"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.etc_pihole.metadata.0.name
          }
        }
        volume {
          name = "dnsmasq-pihole"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.dnsmasq_pihole.metadata.0.name
          }
        }
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

resource "kubernetes_service" "pihole_dns" {
  metadata {
    name      = "pihole-dns"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }
  spec {
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

resource "kubernetes_ingress" "pihole_ingress" {
  metadata {
    name      = "pihole-ingress"
    namespace = kubernetes_namespace.pi_hole.metadata.0.name
  }

  spec {
    rule {
      host = "pihole.internal"
      http {
        path {
          backend {
            service_name = kubernetes_service.pihole_web.metadata.0.name
            service_port = 80
          }
        }
      }
    }

  }
}
