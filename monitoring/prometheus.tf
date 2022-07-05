resource "kubernetes_service" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
    annotations = {
      prometheus_io_scrape = true
    }
  }
  spec {
    selector = {
      name = "prometheus"
    }
    port {
      port = 9090
    }
  }
}

resource "kubernetes_cluster_role" "prometheus" {
  metadata {
    name = "prometheus-role"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/metrics", "services", "endpoints", "pods", "metrics"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }
}

resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus-service-account"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

resource "kubernetes_cluster_role_binding" "prometheus" {
  metadata {
    name = "prometheus-cluster-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.prometheus.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus.metadata.0.name
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

resource "kubernetes_config_map" "prometheus_yml" {
  metadata {
    name      = "prometheus-yml-${sha1(file("${path.module}/config/prometheus.yml"))}-${sha1(file("${path.module}/config/rules.yml"))}"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "prometheus.yml" = "${file("${path.module}/config/prometheus.yml")}"
    "rules.yml" = "${file("${path.module}/config/rules.yml")}"
  }
}

resource "kubernetes_stateful_set" "prometheus" {
  wait_for_rollout = false
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "prometheus"
      }
    }
    service_name = kubernetes_service.prometheus.metadata.0.name

    template {
      metadata {
        labels = {
          name = "prometheus"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.prometheus.metadata.0.name

        init_container {
          name              = "init-chown-data"
          image             = "busybox:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["chown", "-R", "nobody:nobody", "/prometheus"]

          volume_mount {
            name       = "prometheus-data"
            mount_path = "/prometheus"
            sub_path   = ""
          }
        }
        volume {
          name = "prometheus-yml"
          config_map {
            name = kubernetes_config_map.prometheus_yml.metadata.0.name
          }
        }

        container {
          name  = "prometheus"
          image = "prom/prometheus:v2.29.2"
          volume_mount {
            name       = "prometheus-data"
            mount_path = "/prometheus"
          }

          volume_mount {
            name       = "prometheus-yml"
            mount_path = "/etc/prometheus"
          }

          resources {
            requests = {
              cpu = "1"
              memory = "4Gi"
            }
            limits = {
                cpu = "12"
                memory = "4Gi"
            }
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "prometheus-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "100Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "prometheus_ingress" {
  metadata {
    name      = "prometheus-ingress"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  spec {
    rule {
      host = "prometheus.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service.prometheus.metadata.0.name
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }
}

module "prometheus_dns" {
  source   = "../pi-hole-service"

  record  = "prometheus.${var.domain}"
  ingress = kubernetes_ingress_v1.prometheus_ingress
}
