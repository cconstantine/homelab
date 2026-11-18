# kube-state-metrics: exports object state from the API server -- the source
# of pod resource requests/limits (kube_pod_container_resource_requests) and
# node allocatable (kube_node_status_allocatable) that the scheduler packs
# against. cAdvisor only has actual usage. Feeds the "Resource reservations"
# dashboard; scraped by the kubernetes-service-endpoints job via the service
# annotation.

locals {
  # Only what the reservations dashboard needs, to keep cardinality down.
  ksm_resources = [
    "nodes",
    "pods",
    "namespaces",
    "persistentvolumeclaims",
    "deployments",
    "statefulsets",
    "daemonsets",
  ]
}

resource "kubernetes_service_account" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

resource "kubernetes_cluster_role" "kube_state_metrics" {
  metadata {
    name = "kube-state-metrics"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "pods", "namespaces", "persistentvolumeclaims"]
    verbs      = ["list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets"]
    verbs      = ["list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "kube_state_metrics" {
  metadata {
    name = "kube-state-metrics"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.kube_state_metrics.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.kube_state_metrics.metadata.0.name
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

resource "kubernetes_deployment" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
  wait_for_rollout = false
  spec {
    replicas = 1
    selector {
      match_labels = {
        name = "kube-state-metrics"
      }
    }
    template {
      metadata {
        labels = {
          name = "kube-state-metrics"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.kube_state_metrics.metadata.0.name

        container {
          name  = "kube-state-metrics"
          image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.16.0"

          args = [
            "--port=8080",
            "--telemetry-port=8081",
            "--resources=${join(",", local.ksm_resources)}",
          ]

          port {
            name           = "http-metrics"
            container_port = 8080
          }
          port {
            name           = "telemetry"
            container_port = 8081
          }

          liveness_probe {
            http_get {
              path = "/livez"
              port = 8080
            }
            initial_delay_seconds = 5
          }
          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8081
            }
            initial_delay_seconds = 5
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
    annotations = {
      prometheus_io_scrape = true
      prometheus_io_port   = 8080
    }
  }
  spec {
    selector = {
      name = "kube-state-metrics"
    }
    port {
      name        = "http-metrics"
      port        = 8080
      target_port = 8080
    }
  }
}
