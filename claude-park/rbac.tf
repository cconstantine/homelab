resource "kubernetes_service_account" "park" {
  metadata {
    name      = "park"
    namespace = kubernetes_namespace.claude_park.metadata.0.name
  }
}

resource "kubernetes_role" "park" {
  metadata {
    name      = "park"
    namespace = kubernetes_namespace.claude_park.metadata.0.name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create", "get"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "create", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "create", "delete", "patch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "create", "delete", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list"]
  }
  # Whether a Service actually has backends behind it. Without this, "the ingress
  # answers Bad gateway but the container is running" can only be diagnosed from
  # inside the pod. EndpointSlices as well, since Endpoints is deprecated and
  # tooling is moving off it.
  rule {
    api_groups = [""]
    resources  = ["endpoints"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["resourcequotas", "limitranges"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding" "park" {
  metadata {
    name      = "park"
    namespace = kubernetes_namespace.claude_park.metadata.0.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.park.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.park.metadata.0.name
    namespace = kubernetes_namespace.claude_park.metadata.0.name
  }
}

# Since k8s 1.24 a ServiceAccount gets no token Secret automatically; this
# annotation is what tells the API server to mint one into .data here.
resource "kubernetes_secret" "park_token" {
  metadata {
    name      = "park-token"
    namespace = kubernetes_namespace.claude_park.metadata.0.name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.park.metadata.0.name
    }
  }
  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_service_account.park]
}
