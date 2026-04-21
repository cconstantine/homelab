resource "kubernetes_namespace" "namespace" {
  metadata {
    name = "nvidia-device-plugin"
  }
}
