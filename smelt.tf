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

  image         = "ghcr.io/cconstantine/smelt:c0a089794fc7"
  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:c0a089794fc7"

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
