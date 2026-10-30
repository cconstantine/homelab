# A ServiceAccount that can run `terraform apply -target=module.smelt` from
# this repo and nothing wider: the objects the smelt module manages in
# smelt-park, the smelt-park namespace object itself, and this repo's state.
#
# The account lives in its own namespace, not smelt-park: smelt's `park`
# account (smelt and every sandbox) can create pods in smelt-park, and a pod
# may run as any ServiceAccount of its namespace -- a sandbox could otherwise
# start a pod as the deployer and take its rights.
#
# The state is the catch: it's one Secret for the whole repo, so this account
# can read every secret Terraform holds (Cloudflare token, GitHub PATs, ...).
# Scoping that further means giving smelt a state of its own.
#
# A job using it writes a kubeconfig whose context is named `default` (what
# provider.tf and the backend select), pointing at the in-cluster API with the
# pod's ServiceAccount token, and runs with the root variables that have no
# default set to anything (the smelt module uses none of them).

variable "smelt_namespace" {
  description = "Where the smelt module's objects live."
  type        = string
  default     = "smelt-park"
}

locals {
  # The kubernetes backend's objects for the default workspace
  # (backend "kubernetes" { secret_suffix = "state" } in provider.tf).
  state_namespace = "default"
  state_secret    = "tfstate-default-state"
  state_lease     = "lock-tfstate-default-state"
}

resource "kubernetes_namespace" "smelt_deploy" {
  metadata {
    name = "smelt-deploy"
  }
}

resource "kubernetes_service_account" "smelt_deployer" {
  metadata {
    name      = "smelt-deployer"
    namespace = kubernetes_namespace.smelt_deploy.metadata.0.name
  }
}

# Everything module.smelt creates in smelt-park.
resource "kubernetes_role" "smelt_deployer" {
  metadata {
    name      = "smelt-deployer"
    namespace = var.smelt_namespace
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["services", "secrets", "serviceaccounts", "limitranges"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  # The module's `park` Role grants pod exec, port-forward and more that this
  # account doesn't hold itself; Kubernetes only lets it write and bind that
  # Role with `escalate` and `bind` on it -- on that one Role, nothing else.
  rule {
    api_groups     = ["rbac.authorization.k8s.io"]
    resources      = ["roles"]
    resource_names = ["park"]
    verbs          = ["escalate", "bind"]
  }
}

resource "kubernetes_role_binding" "smelt_deployer" {
  metadata {
    name      = "smelt-deployer"
    namespace = var.smelt_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.smelt_deployer.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.smelt_deployer.metadata.0.name
    namespace = kubernetes_namespace.smelt_deploy.metadata.0.name
  }
}

# The module manages the smelt-park Namespace object too. Read and patch it,
# by name; no create or delete, so even a stray destroy can't remove it.
resource "kubernetes_cluster_role" "smelt_deployer" {
  metadata {
    name = "smelt-deployer"
  }

  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = [var.smelt_namespace]
    verbs          = ["get", "update", "patch"]
  }
  # smelt.tf takes its OTEL endpoint from module.monitoring's tempo Service, so
  # -target=module.smelt refreshes that namespace and Service too. Read only:
  # a targeted apply that wanted to change them fails instead.
  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = ["monitoring"]
    verbs          = ["get"]
  }
}

resource "kubernetes_role" "smelt_deployer_monitoring" {
  metadata {
    name      = "smelt-deployer"
    namespace = "monitoring"
  }

  rule {
    api_groups     = [""]
    resources      = ["services"]
    resource_names = ["tempo"]
    verbs          = ["get"]
  }
}

resource "kubernetes_role_binding" "smelt_deployer_monitoring" {
  metadata {
    name      = "smelt-deployer"
    namespace = "monitoring"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.smelt_deployer_monitoring.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.smelt_deployer.metadata.0.name
    namespace = kubernetes_namespace.smelt_deploy.metadata.0.name
  }
}

resource "kubernetes_cluster_role_binding" "smelt_deployer" {
  metadata {
    name = "smelt-deployer"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.smelt_deployer.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.smelt_deployer.metadata.0.name
    namespace = kubernetes_namespace.smelt_deploy.metadata.0.name
  }
}

# This repo's state and its lock. `list` can't be limited to a name (the
# backend lists its secrets by label to find workspaces); today the state is
# the only Secret in `default`.
resource "kubernetes_role" "smelt_deployer_state" {
  metadata {
    name      = "smelt-deployer-state"
    namespace = local.state_namespace
  }

  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [local.state_secret]
    verbs          = ["get", "update", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["list"]
  }
  rule {
    api_groups     = ["coordination.k8s.io"]
    resources      = ["leases"]
    resource_names = [local.state_lease]
    verbs          = ["get", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "smelt_deployer_state" {
  metadata {
    name      = "smelt-deployer-state"
    namespace = local.state_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.smelt_deployer_state.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.smelt_deployer.metadata.0.name
    namespace = kubernetes_namespace.smelt_deploy.metadata.0.name
  }
}

output "namespace" {
  value = kubernetes_namespace.smelt_deploy.metadata.0.name
}

output "service_account" {
  value = kubernetes_service_account.smelt_deployer.metadata.0.name
}
