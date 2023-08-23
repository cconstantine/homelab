resource "kubernetes_namespace" "wireguard" {
  metadata {
    name = "wireguard"
  }
}
