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
