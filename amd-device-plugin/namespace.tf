resource "kubernetes_namespace" "namespace" {
  metadata {
    name = "amd-device-plugin"
  }
}
