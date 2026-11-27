# smelt, deployed from the module kept in the smelt repo itself.

# The module lives in the smelt repo (`terraform/smelt`) so it ships with the
# app it deploys — RBAC, env names and image layout change together and the
# module changes with them, reviewed in the same PR. It is tested there against
# a k3d cluster (`terraform/test-cluster`), including smelt's own
# real-cluster pod-lifecycle test.

# The images are what smelt's publish-images workflow pushes to GHCR, tagged
# with the 12-character SHA of the smelt main commit they were built from. A
# deploy (smelt-deployer/DEPLOY.md) sets three lines to the same SHA: the
# module source's `?ref=`, `image` and `sandbox_image`, so the module code and
# the images always come from one commit (SME-663). A changed ref needs
# `terraform init` again before the plan.
# The smelt repo is private: the module is fetched over SSH, so `terraform
# init` needs a GitHub key with read access to cconstantine/smelt.

module "smelt" {
  source = "git::ssh://git@github.com/cconstantine/smelt.git//terraform/smelt?ref=52e14d865f08"

  image         = "ghcr.io/cconstantine/smelt:52e14d865f08"
  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:52e14d865f08"

  # Lets smelt read PersistentVolumes and StorageClasses cluster-wide, so its
  # Sandboxes page shows the claims' class and their Released volumes
  # (SME-521). The smelt deployer holds those reads itself so it can make the
  # ClusterRole; see smelt-deployer/main.tf.
  storage_reader_enabled = true

  # Memory request and limit for the server container. Raised from the module
  # default 2Gi after one OOMKill at that limit under ordinary load (SME-764);
  # PM-decided 2026-11-25 (SME-823).
  server_memory = "3072Mi"

  # smelt.constantlee.us, a record of the globally-resolved domain every
  # *.constantlee.us name has TLS under. The module's default base URL —
  # `https://<domain>` — is therefore right here, unlike the `.homelab`
  # services that terminate nothing.
  #
  # Previews stay off (they want a wildcard DNS record of their own and, for
  # one-label TLS coverage, the apex domain as the preview domain). Setting
  preview_domain = "preview.smelt.constantlee.us"
  domain         = "smelt.constantlee.us"

  # Traces to Tempo in the monitoring namespace, read in Grafana (Explore →
  # Tempo → TraceQL, e.g. `{ resource.service.name = "smelt" }`).
  extra_env = {
    OTEL_EXPORTER_OTLP_ENDPOINT = module.monitoring.tempo_otlp_http_endpoint
    SANDBOX_NODE_SELECTOR       = "kubernetes.io/arch=amd64"
    # Ordinary stops' storage ages out after 2 days rather than smelt's
    # default 7 (the user, 2026-11-21, SME-684: framework's disk filled with
    # week-old Driver volumes); finished agents keep the 1-day default.
    # The user's Stop, and pre-SME-521 stops whose cause can't be told,
    # also get 2 days rather than 30 (the user, 2026-11-21).
    SANDBOX_STORAGE_REMOVAL_DAYS      = "2"
    SANDBOX_USER_STOPPED_STORAGE_DAYS = "2"
    # Sandbox storage claims: the
    # claims take the cluster's default class — k3s's stock local-path, a
    # Delete reclaim with a provisioner, unlike the hand-made PVs behind the
    # no-provisioner local-storage class other workloads use — and
    # storage_reader_enabled above lets smelt report the class and any
    # Released volume that stops reclaiming.
  }
}
