locals {
  # Bookable space per replica node. Longhorn books a volume's full size when
  # placing a replica, so this caps how many replicas (and how much
  # instance-manager memory) each node takes on. storageReserved is the disk's
  # size minus the cap; sizes are the filesystem sizes node_exporter reports.
  replica_disks = {
    # SATA SSD shared with the k3s datastore and sandbox volumes; the default
    # /var/lib/longhorn would be on the small root disk.
    homelab = {
      path       = "/var/lib/rancher/longhorn"
      size_bytes = 983351140352
      cap_bytes  = 100 * 1024 * 1024 * 1024
    }
    # Strata's workstation: replicas only, no engines (see longhorn-plan.md).
    ryzen = {
      path       = "/var/lib/longhorn"
      size_bytes = 1963602735104
      cap_bytes  = 200 * 1024 * 1024 * 1024
    }
    cachyos-x8664 = {
      path       = "/var/lib/longhorn"
      size_bytes = 1963617406976
      cap_bytes  = 200 * 1024 * 1024 * 1024
    }
  }

  # These run Longhorn so pods there can attach volumes, but hold no replicas
  # (no create-default-disk label, so Longhorn gives them no disk). framework
  # is the laptop, which leaves the network: a volume attached there is
  # unavailable until the pod is rescheduled, but no data lives on it.
  attach_only_nodes = ["system76", "framework"]

  longhorn_nodes = toset(concat(keys(local.replica_disks), local.attach_only_nodes))

  # The Deployments that aren't tied to a node stay off ryzen (kept free for
  # Strata) and framework (it leaves).
  control_nodes = setsubtract(local.longhorn_nodes, ["ryzen", "framework"])
}

# Each resource has its own server-side-apply field manager, so applying it
# can't drop labels other Terraform resources own (see the comment on
# kubernetes_node_taint.ryzen in amd-device-plugin/main.tf).
resource "kubernetes_labels" "node" {
  for_each = local.longhorn_nodes

  api_version   = "v1"
  kind          = "Node"
  field_manager = "terraform-longhorn"
  metadata {
    name = each.key
  }
  labels = merge(
    { "homelab/longhorn" = "true" },
    contains(local.control_nodes, each.key) ? { "homelab/longhorn-control" = "true" } : {},
    contains(keys(local.replica_disks), each.key) ? { "node.longhorn.io/create-default-disk" = "config" } : {},
  )
}

# Longhorn reads this only when it first adds a node that has no disks, so it
# has to be in place before the chart is installed. Changing it later does
# nothing; edit the disk through Longhorn instead.
resource "kubernetes_annotations" "default_disks" {
  for_each = local.replica_disks

  api_version   = "v1"
  kind          = "Node"
  field_manager = "terraform-longhorn-disks"
  metadata {
    name = each.key
  }
  annotations = {
    "node.longhorn.io/default-disks-config" = jsonencode([{
      name            = "default-disk"
      path            = each.value.path
      allowScheduling = true
      storageReserved = each.value.size_bytes - each.value.cap_bytes
    }])
  }
}
