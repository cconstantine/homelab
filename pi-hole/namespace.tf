resource "kubernetes_namespace" "pi_hole" {
  metadata {
    name = "pihole"
  }
}
