# OmniRoute (https://github.com/diegosouzapw/OmniRoute): OpenAI-compatible AI
# gateway. Deployed here so it can front both the local llama-cpp-ryzen model
# and (once configured) Claude via a real Anthropic API key, from one
# endpoint reachable anywhere on the LAN.
#
# Deliberately NOT using OMNIROUTE_SELF_HOSTED_PROVIDERS: that env var turns
# /v1/chat/completions into a self-hosted-only gateway and stops falling
# through to the normal cloud provider catalog entirely, which would break
# using Anthropic through the same endpoint. Instead, llama-cpp-ryzen and
# Anthropic are both added as ordinary providers through the OmniRoute
# dashboard/API after this deploys -- that's app-level runtime config (stored
# encrypted in its own DB on the PVC below), not infrastructure, so it
# doesn't belong in Terraform.
#
# Scheduled on the "homelab" control-plane node rather than ryzen/xavier:
# OmniRoute is just a Node.js gateway (no GPU use), and ryzen's RAM is
# already heavily committed to the llama-cpp-ryzen model.
locals {
  local_storage_class = "local-storage"
  storage_node        = "homelab"
}

# INITIAL_PASSWORD is required (no built-in safe default -- the image ships
# with the obviously-insecure 'CHANGEME' and expects the operator to
# override it) since the dashboard is reachable from the whole LAN via
# ingress. Change it via Dashboard -> Settings -> Security after first
# login; this Terraform-managed value then only matters again if the pod's
# data volume is ever wiped. random_pet (word-word-word-word) instead of
# random_password so it's actually typeable by hand, not just copy-pasteable.
resource "random_pet" "omniroute_initial_password" {
  length    = 4
  separator = "-"
}

resource "kubernetes_secret" "omniroute" {
  metadata {
    name      = "omniroute"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  data = {
    INITIAL_PASSWORD = random_pet.omniroute_initial_password.id
  }
}

resource "kubernetes_persistent_volume" "omniroute_data" {
  metadata {
    name = "omniroute-data"
    labels = {
      type = "local"
      app  = "omniroute"
      use  = "data"
    }
  }
  spec {
    capacity = {
      storage = "20Gi"
    }
    access_modes                     = ["ReadWriteOnce"]
    storage_class_name               = local.local_storage_class
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      local {
        path = "/storage/omniroute/data"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [local.storage_node]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "omniroute_data" {
  metadata {
    name      = "omniroute-data"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.local_storage_class
    resources {
      requests = {
        storage = "20Gi"
      }
    }
    selector {
      match_labels = {
        type = "local"
        app  = "omniroute"
        use  = "data"
      }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_service_v1" "omniroute" {
  metadata {
    name      = "omniroute"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    selector = {
      name = "omniroute"
    }
    port {
      port        = 20128
      target_port = 20128
    }
  }
}

resource "kubernetes_deployment_v1" "omniroute" {
  metadata {
    name      = "omniroute"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        name = "omniroute"
      }
    }

    template {
      metadata {
        labels = {
          name = "omniroute"
        }
      }
      spec {
        node_selector = {
          "kubernetes.io/hostname" = local.storage_node
        }

        container {
          name              = "omniroute"
          image             = "diegosouzapw/omniroute:3.8.50"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 20128
          }

          # Sized per docs/guides/DOCKER_GUIDE.md's "one coding agent"
          # tier -- Claude Code/Codex-style /v1/responses calls need a much
          # bigger V8 heap than the 1024MB dashboard-only default or the
          # process FATAL ERRORs under long contexts.
          env {
            name  = "OMNIROUTE_MEMORY_MB"
            value = "8192"
          }
          # Required for the dashboard to accept adding llama-cpp-ryzen as a
          # provider: its ingress resolves to a private LAN address, which
          # OmniRoute's SSRF guard blocks by default.
          env {
            name  = "OMNIROUTE_ALLOW_PRIVATE_PROVIDER_URLS"
            value = "true"
          }
          env {
            name  = "NEXT_PUBLIC_BASE_URL"
            value = "https://omniroute.${var.tls_domain}"
          }
          env {
            name = "INITIAL_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.omniroute.metadata.0.name
                key  = "INITIAL_PASSWORD"
              }
            }
          }
          # Reachable from the whole LAN via ingress, and anonymous /v1
          # calls would otherwise spend real Anthropic API budget -- require
          # a key (generate one via Dashboard -> Endpoints after login).
          env {
            name  = "REQUIRE_API_KEY"
            value = "true"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "2Gi"
            }
            limits = {
              cpu    = "4"
              memory = "10Gi"
            }
          }

          volume_mount {
            name       = "omniroute-data"
            mount_path = "/app/data"
          }
        }

        volume {
          name = "omniroute-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.omniroute_data.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "omniroute" {
  metadata {
    name      = "omniroute"
    namespace = kubernetes_namespace.namespace.metadata.0.name
  }

  spec {
    rule {
      host = "omniroute.${var.domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.omniroute.metadata.0.name
              port {
                number = 20128
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "omniroute_tls" {
  metadata {
    name      = "omniroute-tls"
    namespace = kubernetes_namespace.namespace.metadata.0.name
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "cert-manager-redirect-https@kubernetescrd,cert-manager-hsts-headers@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "omniroute.${var.tls_domain}"
      http {
        path {
          backend {
            service {
              name = kubernetes_service_v1.omniroute.metadata.0.name
              port {
                number = 20128
              }
            }
          }
        }
      }
    }
  }
}
