resource "kubernetes_namespace" "longhorn" {
  metadata {
    name = "longhorn-system"
  }
}

resource "helm_release" "longhorn" {
  name       = "longhorn"
  namespace  = kubernetes_namespace.longhorn.metadata.0.name
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.13.0"

  values = [file("${path.module}/values.yaml")]

  # Node labels and disk annotations must exist before Longhorn first sees
  # the nodes (nodes.tf).
  depends_on = [
    kubernetes_labels.node,
    kubernetes_annotations.default_disks,
  ]

  wait    = true
  timeout = 900
}

# Two replicas, for apps moved off local-path. The chart's own "longhorn"
# class (3 replicas, Delete) is left as the chart makes it.
#
# Delete: deleting a PVC deletes its Longhorn volume, so released volumes
# don't pile up. PVs created while the class was Retain keep Retain (the
# policy is copied onto each PV at provisioning).
#
# best-effort data locality: when a volume attaches on a node with a Longhorn
# disk but no replica, Longhorn builds a replica there and then drops one
# elsewhere, so the data follows the pod. Each move copies the whole volume
# over the network. system76 has no disk, so volumes used there stay remote.
# StorageClass parameters are immutable: changing them recreates the class,
# which doesn't touch existing volumes (each keeps its own spec.dataLocality).
resource "kubernetes_storage_class" "longhorn_r2" {
  metadata {
    name = "longhorn-r2"
  }
  storage_provisioner    = "driver.longhorn.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true
  parameters = {
    numberOfReplicas    = "2"
    staleReplicaTimeout = "30"
    fsType              = "ext4"
    dataLocality        = "best-effort"
  }

  depends_on = [helm_release.longhorn]
}
