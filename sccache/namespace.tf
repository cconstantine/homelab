resource "kubernetes_namespace" "sccache" {
  metadata {
    name = "sccache"
  }
}
