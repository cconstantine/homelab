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

# The Claude Code provider's subscription token (SME-438). It reaches the smelt
# server only through the module's `secret_env` (a Kubernetes Secret and a
# secretKeyRef, never a plain env value). The smelt deployer exports it as
# TF_VAR_claude_code_oauth_token from its `claude_oauth_token` smelt secret; it
# is never written in this repo. It has no default and must look like a real
# `claude setup-token` token, so any plan that includes module.smelt without it
# (or with a placeholder like "unused") fails at plan instead of clearing it.
variable "claude_code_oauth_token" {
  description = "CLAUDE_CODE_OAUTH_TOKEN for smelt's Claude Code provider, from `claude setup-token`."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.claude_code_oauth_token, "sk-ant-oat")
    error_message = "claude_code_oauth_token must be a real `claude setup-token` token (sk-ant-oat...): export TF_VAR_claude_code_oauth_token, never a placeholder."
  }
}

module "smelt" {
  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=main"

  image         = "ghcr.io/cconstantine/smelt:f85b3b06469f"
  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:f85b3b06469f"

  # smelt.constantlee.us, a record of the globally-resolved domain every
  # *.constantlee.us name has TLS under. The module's default base URL —
  # `https://<domain>` — is therefore right here, unlike the `.homelab`
  # services that terminate nothing.
  #
  # Previews stay off (they want a wildcard DNS record of their own and, for
  # one-label TLS coverage, the apex domain as the preview domain). Setting
  preview_domain = "preview.smelt.constantlee.us"
  domain         = "smelt.constantlee.us"

  # The Claude Code token, from the variable above (SME-438).
  secret_env = {
    CLAUDE_CODE_OAUTH_TOKEN = var.claude_code_oauth_token
  }

  # Traces to Tempo in the monitoring namespace, read in Grafana (Explore →
  # Tempo → TraceQL, e.g. `{ resource.service.name = "smelt" }`).
  extra_env = {
    OTEL_EXPORTER_OTLP_ENDPOINT = module.monitoring.tempo_otlp_http_endpoint
    SANDBOX_NODE_SELECTOR = "kubernetes.io/arch=amd64"
  }
}
