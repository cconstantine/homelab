# The cluster-wide grant smelt's volume move needs (SME-552), matching
# smelt's k8s/smelt-volume-mover.yaml.
#
# When a returning conversation's pod can't be scheduled because its
# `/workspace` claim's volume pins it to a node with no room, smelt moves that
# claim: it sets the old PersistentVolume's reclaim policy to Retain and labels
# it, patches its claimRef over to a holder claim, lists volumes by those
# labels to repair a move a crash cut short, and sets the policy back to Delete
# once the data is copied. Without this grant a move fails at its first read of
# the volume (403), changes nothing, and the start fails as before.
#
# No create or delete: the provisioner still makes and removes every volume.
#
# This lives outside module.smelt on purpose: the smelt deployer
# (smelt-deployer/main.tf) holds only get/list on PersistentVolumes, and
# Kubernetes refuses a role granting more than its creator holds, so a
# deployer run can't create it. Apply it as an admin:
#
#   terraform apply -target=kubernetes_cluster_role_v1.smelt_volume_mover \
#                   -target=kubernetes_cluster_role_binding_v1.smelt_volume_mover
resource "kubernetes_cluster_role_v1" "smelt_volume_mover" {
  metadata {
    name = "smelt-volume-mover"
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumes"]
    verbs      = ["get", "list", "patch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "smelt_volume_mover" {
  metadata {
    name = "smelt-volume-mover"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.smelt_volume_mover.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "park"
    namespace = "smelt-park"
  }
}
