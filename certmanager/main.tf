resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata.0.name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.21.1"

  set = [{
    name  = "crds.enabled"
    value = "true"
  }]

  values = [yamlencode({
    resources = {
      requests = { cpu = "10m", memory = "80Mi" }
      limits   = { memory = "112Mi" }
    }
    cainjector = {
      resources = {
        requests = { cpu = "10m", memory = "64Mi" }
        limits   = { memory = "96Mi" }
      }
    }
    webhook = {
      resources = {
        requests = { cpu = "10m", memory = "48Mi" }
        limits   = { memory = "80Mi" }
      }
    }
  })]

  wait = true
}

resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = kubernetes_namespace.cert_manager.metadata.0.name
  }

  data = {
    api-token = var.cloudflare_api_token
  }
}

resource "kubectl_manifest" "letsencrypt_dns01" {
  depends_on = [helm_release.cert_manager]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-dns01"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-dns01-account-key"
        }
        solvers = [{
          dns01 = {
            cloudflare = {
              apiTokenSecretRef = {
                name = kubernetes_secret.cloudflare_api_token.metadata.0.name
                key  = "api-token"
              }
            }
          }
        }]
      }
    }
  })
}

resource "kubectl_manifest" "wildcard_certificate" {
  depends_on = [kubectl_manifest.letsencrypt_dns01]

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-constantlee-us"
      namespace = kubernetes_namespace.cert_manager.metadata.0.name
    }
    spec = {
      secretName = "wildcard-constantlee-us-tls"
      issuerRef = {
        name = "letsencrypt-dns01"
        kind = "ClusterIssuer"
      }
      dnsNames = var.tls_domains
    }
  })
}

# Traefik only recognizes one TLSStore, named "default", cluster-wide - it's
# what every Ingress falls back to when no other cert matches its SNI, so no
# per-service tls block is needed for hosts under the wildcard.
resource "kubectl_manifest" "default_tls_store" {
  depends_on = [kubectl_manifest.wildcard_certificate]

  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "TLSStore"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace.cert_manager.metadata.0.name
    }
    spec = {
      defaultCertificate = {
        secretName = "wildcard-constantlee-us-tls"
      }
    }
  })
}

# Traefik's Middleware CRD is namespace-scoped by default: an Ingress can
# only reference a Middleware in its own namespace. This lets any namespace
# reference the ones below (defined once here) via
# "cert-manager-<name>@kubernetescrd" instead of duplicating them per
# service namespace.
resource "kubectl_manifest" "traefik_allow_cross_namespace" {
  yaml_body = yamlencode({
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata = {
      name      = "traefik"
      namespace = "kube-system"
    }
    spec = {
      valuesContent = yamlencode({
        providers = {
          kubernetesCRD = {
            allowCrossNamespace = true
          }
        }
      })
    }
  })
}

resource "kubectl_manifest" "redirect_https_middleware" {
  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "redirect-https"
      namespace = kubernetes_namespace.cert_manager.metadata.0.name
    }
    spec = {
      redirectScheme = {
        scheme    = "https"
        permanent = true
      }
    }
  })
}

resource "kubectl_manifest" "hsts_headers_middleware" {
  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "hsts-headers"
      namespace = kubernetes_namespace.cert_manager.metadata.0.name
    }
    spec = {
      headers = {
        stsSeconds           = 31536000
        stsIncludeSubdomains = true
      }
    }
  })
}
