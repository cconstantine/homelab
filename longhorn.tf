# Replicated block storage for small, low-write app volumes. See
# longhorn-plan.md for the rollout and which apps move.
module "longhorn" {
  source = "./longhorn-storage"
}
