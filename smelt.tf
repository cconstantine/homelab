# smelt, deployed from the module kept in the smelt repo itself.

# The module lives in the smelt repo (`terraform/smelt`) so it ships with the
# app it deploys — RBAC, env names and image layout change together and the
# module changes with them, reviewed in the same PR. It is tested there against
# a k3d cluster (`terraform/test-cluster`), including smelt's own
# real-cluster pod-lifecycle test.

# The images are what smelt's publish-images workflow pushes to GHCR. The
# `:latest` tag tracks main, so this deploy follows smelt without tag edits:
# `terraform plan && terraform apply` picks up whatever main built last. The
# catch is that a moving tag doesn't make a running Deployment roll (its pod
# template never changes and the pull policy is IfNotPresent), so a restarted
# pod — or `kubectl rollout restart` — is what actually pulls the new image.

module "smelt" {
  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=main"

  image         = "ghcr.io/cconstantine/smelt:latest"
  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:latest"

  # smelt.constantlee.us, a record of the globally-resolved domain every
  # *.constantlee.us name has TLS under. The module's default base URL —
  # `https://<domain>` — is therefore right here, unlike the `.homelab`
  # services that terminate nothing.
  #
  # Previews stay off (they want a wildcard DNS record of their own and, for
  # one-label TLS coverage, the apex domain as the preview domain). Setting
  # `preview_domain = "constantlee.us"` turns them on when that's wanted.
  domain = "smelt.constantlee.us"
}
