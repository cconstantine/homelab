terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    pihole = {
      source = "ryanwholey/pihole"
    }
    tls = {
      source = "hashicorp/tls"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }
  backend "kubernetes" {
    secret_suffix = "state"
    config_path   = "~/.kube/config"
  }

}

provider "pihole" {
  url      = module.pi_hole.url
  password = module.pi_hole.password
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "default"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "default"
  }
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "default"
}
