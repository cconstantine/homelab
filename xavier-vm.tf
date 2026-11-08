# xavier-vm is the k3s agent in a Firecracker VM on the Xavier (8 slow
# Carmel cores, no GPU). It's there for the arm runners and smelt sandboxes,
# so other pods should go elsewhere when they can.
#
# Unlike ryzen's NoSchedule, PreferNoSchedule is a soft taint: the scheduler
# ranks this node last, but still uses it when it's the only node that fits
# (the arm runners, or a pod that doesn't fit anywhere else). A pod that
# tolerates homelab/vm=firecracker opts in without the penalty. Running pods
# aren't moved, and DaemonSets aren't affected.
resource "kubernetes_node_taint" "xavier_vm" {
  metadata {
    name = "xavier-vm"
  }
  # Its own server-side-apply manager, as with ryzen's taint
  # (amd-device-plugin/main.tf), so applying it can't drop other node fields.
  field_manager = "terraform-xavier-vm-taint"
  taint {
    key    = "homelab/vm"
    value  = "firecracker"
    effect = "PreferNoSchedule"
  }
}
