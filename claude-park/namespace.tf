resource "kubernetes_namespace" "claude_park" {
  metadata {
    name = var.name
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# No ResourceQuota on storage, deliberately. It could not do the job people expect of
# it here: local-path PVCs are directories on the node, so a claim's size is a label,
# not a reservation or a limit -- a "40Gi" volume reports the node's whole filesystem
# and can grow until the disk is full. Quotaing requests.storage therefore bounded
# nothing real while still refusing parks that would have fit: three parks using a few
# GB between them booked 240Gi of a 400Gi quota. Parks are launched by hand; disk is
# watched on the node, and bin/park fails fast if a pod cannot schedule.
