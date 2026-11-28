terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    # kubectl_manifest (the prometheus-admin-auth Middleware, SME-922):
    # without this the module resolves kubectl to hashicorp/kubectl, which
    # doesn't exist. Same source as the root and certmanager/.
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
}
