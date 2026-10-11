# smelt, deployed from the module kept in the smelt repo itself.

# The module lives in the smelt repo (`terraform/smelt`) so it ships with the
# app it deploys — RBAC, env names and image layout change together and the
# module changes with them, reviewed in the same PR. It is tested there against
# a k3d cluster (`terraform/test-cluster`), including smelt's own
# real-cluster pod-lifecycle test.

# The images are what smelt's publish-images workflow pushes to GHCR, tagged by
# commit; updating smelt is changing these two tags and re-applying.

module "smelt" {
  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=main"

  # ref=main needs the terraform-module PR merged; until then, point it at
  # that branch. Both GHCR tags below are pushed already (the workflow builds
  # from branches, not just main).
  image         = "ghcr.io/cconstantine/smelt:c0a089794fc7"
  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:c0a089794fc7"

  domain   = "smelt.homelab"
  base_url = "http://smelt.homelab" # no TLS at the ingress, as everywhere else here
}
