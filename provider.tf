terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.4.1"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0.1"
    }
  }
}
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "default"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "default"
}

data "terraform_remote_state" "foo" {
  backend = "kubernetes"
  config = {
    secret_suffix    = "state"
    load_config_file = true
    config_path      = "~/.kube/config"
  }
}