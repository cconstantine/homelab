resource "kubernetes_namespace" "astro" {
  metadata {
    name = var.namespace
  }
}
