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

resource "kubernetes_persistent_volume" "prometheus_local_data" {
  metadata {
    name = "prometheus-local-data"
    labels = {
      type = "local"
      app  = "prometheus"
    }
  }
  spec {
    capacity = {
      storage = "100Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "local-storage"
    persistent_volume_source {
      local {
        path = "/storage/prometheus/data"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = ["homelab"]
          }
        }
      }
    }
  }
}

# Create a storage class for local storage
resource "kubernetes_storage_class" "local_storage" {
  metadata {
    name = "local-storage"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
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

# The rules-sidecar container (below) reads rule ConfigMaps from smelt-park
# through the API -- a ConfigMap must be in the pod's own namespace to be
# mounted, and smelt-park's are not -- so the prometheus service account needs
# get/list/watch on configmaps there. Namespaced Role, not a ClusterRole: this
# is the only cross-namespace read, and smelt-park's RBAC stays in smelt-park.
# smelt-park is managed outside this module, so it's named by string (same as
# smelt-volume-mover.tf). Applied by the user's admin kubeconfig, like
# everything here.
resource "kubernetes_role" "prometheus_rules_smelt_park" {
  metadata {
    name      = "prometheus-rules-smelt-park"
    namespace = "smelt-park"
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "prometheus_rules_smelt_park" {
  metadata {
    name      = "prometheus-rules-smelt-park"
    namespace = "smelt-park"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.prometheus_rules_smelt_park.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus.metadata.0.name
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }
}

# The sha1 names embedded here cover prometheus.yml and rules.yml only, on
# purpose: rules.d/ is runtime state the rules-sidecar syncs from smelt-park
# ConfigMaps into a shared emptyDir, deliberately outside this ConfigMap -- a
# rule file landing in rules.d must NOT roll the Prometheus pod (SME-903).
resource "kubernetes_config_map" "prometheus_yml" {
  metadata {
    name      = "prometheus-yml-${sha1(file("${path.module}/config/prometheus.yml"))}-${sha1(file("${path.module}/config/rules.yml"))}"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    "prometheus.yml" = "${file("${path.module}/config/prometheus.yml")}"
    "rules.yml"      = "${file("${path.module}/config/rules.yml")}"
  }
}

# Credentials for scrape targets that need them, mounted at
# /etc/prometheus-credentials and named by the jobs' credentials_file.
resource "kubernetes_secret" "prometheus_scrape_credentials" {
  metadata {
    name      = "prometheus-scrape-credentials"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
  }

  data = {
    strata = var.strata_api_key
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
            name       = "prometheus-storage"
            mount_path = "/prometheus"
            sub_path   = ""
          }
        }
        # The rules-sidecar's initial LIST re-sync replaces everything here
        # on a fresh pod, so a pod can never restart onto a *stale* rule
        # file. Prometheus v3.8 parses rule files at startup and exits 2 on an
        # unparseable one, and the emptyDir survives a *container* restart --
        # clearing runs only on pod (re)creation, where it costs nothing and
        # keeps the fresh-pod contract explicit. The contract covers stale
        # files only: a live bad rule ConfigMap is re-written by that same
        # initial LIST, and if the sync wins the startup-parse race the pod
        # crash-loops on exit 2 until the ConfigMap itself is deleted or
        # fixed -- recovery is the ConfigMap, not the pod; SME-904's promtool
        # CI is the mitigation.
        init_container {
          name              = "clear-rules-d"
          image             = "busybox:1.37.0"
          image_pull_policy = "IfNotPresent"
          command           = ["sh", "-c", "rm -rf /etc/prometheus/rules.d/*"]

          volume_mount {
            name       = "rules-d"
            mount_path = "/etc/prometheus/rules.d"
          }
        }
        volume {
          name = "rules-d"

          empty_dir {}
        }
        volume {
          name = "prometheus-yml"
          config_map {
            name = kubernetes_config_map.prometheus_yml.metadata.0.name
          }
        }
        volume {
          name = "prometheus-scrape-credentials"
          secret {
            secret_name = kubernetes_secret.prometheus_scrape_credentials.metadata.0.name
          }
        }

        container {
          name  = "prometheus"
          image = "prom/prometheus:v3.8.0"

          args = [
            "--storage.tsdb.retention.time=365d",
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--web.console.libraries=/usr/share/prometheus/console_libraries",
            "--web.console.templates=/usr/share/prometheus/consoles",
            "--web.enable-admin-api",
            # /-/reload answers 403 without this, and the rules-sidecar below
            # POSTs it on every rule change (SME-903). It also serves
            # /-/quit on :9090 -- same trust boundary as --web.enable-admin-api
            # above, LAN-only; the endpoint hardening is SME-922, not here.
            "--web.enable-lifecycle",
            "--enable-feature=promql-experimental-functions"
          ]

          volume_mount {
            name       = "prometheus-storage"
            mount_path = "/prometheus"
          }

          volume_mount {
            name       = "prometheus-yml"
            mount_path = "/etc/prometheus"
          }

          # Nested under the config-map mount above -- kubelet mounts parents
          # before children, so the two coexist.
          volume_mount {
            name       = "rules-d"
            mount_path = "/etc/prometheus/rules.d"
          }

          volume_mount {
            name       = "prometheus-scrape-credentials"
            mount_path = "/etc/prometheus-credentials"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "2Gi"
            }
            limits = {
              memory = "4Gi"
            }
          }
        }

        # kiwigrid k8s-sidecar (the pattern Grafana's chart uses for
        # dashboards, SME-903): watches ConfigMaps labelled prometheus_rule=1
        # in smelt-park, writes each data key into the shared rules.d emptyDir
        # as a file named after the key, and POSTs /-/reload after every
        # change -- including DELETED, which removes the file first. On start
        # it does an initial LIST sync before watching, so a fresh pod
        # converges from the API. Runs as uid 65534, the same user the
        # prometheus image runs as.
        container {
          name  = "rules-sidecar"
          image = "kiwigrid/k8s-sidecar:2.14.3"

          env {
            name  = "LABEL"
            value = "prometheus_rule"
          }
          env {
            name  = "LABEL_VALUE"
            value = "1"
          }
          env {
            name  = "NAMESPACE"
            value = "smelt-park"
          }
          env {
            name  = "RESOURCE"
            value = "configmap"
          }
          env {
            name  = "FOLDER"
            value = "/etc/prometheus/rules.d"
          }
          env {
            name  = "REQ_URL"
            value = "http://localhost:9090/-/reload"
          }
          env {
            name  = "REQ_METHOD"
            value = "POST"
          }

          volume_mount {
            name       = "rules-d"
            mount_path = "/etc/prometheus/rules.d"
          }

          # /healthz on :8080: 503 until the initial sync is done (readiness),
          # 503 when the watcher threads die (liveness) -- a 403-RBAC sidecar
          # restart-loops instead of silently serving stale rules.
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
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
      }
    }

    volume_claim_template {
      metadata {
        name = "prometheus-storage"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "local-storage"
        resources {
          requests = {
            storage = "100Gi"
          }
        }
        # selector {
        #   match_labels = {
        #     type = "local"
        #     app  = "prometheus"
        #   }
        # }
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

resource "kubernetes_ingress_v1" "prometheus_ingress_tls" {
  metadata {
    name      = "prometheus-ingress-tls"
    namespace = kubernetes_namespace.monitoring.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "prometheus.${var.tls_domain}"
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
  source = "../pi-hole-service"

  record  = "prometheus.${var.domain}"
  ingress = kubernetes_ingress_v1.prometheus_ingress
}
