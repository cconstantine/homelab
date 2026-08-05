resource "kubernetes_namespace" "claude_park" {
  metadata {
    name = "claude-park"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_resource_quota" "claude_park_storage" {
  metadata {
    name      = "claude-park-storage"
    namespace = kubernetes_namespace.claude_park.metadata.0.name
  }
  spec {
    hard = {
      "requests.storage" = var.storage_quota
    }
  }
}
