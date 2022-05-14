terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.4.1"
    }
    pihole = {
      source = "ryanwholey/pihole"
      version = "0.0.11"
    }

  }
  backend "kubernetes" {
    secret_suffix    = "state"
    config_path      = "~/.kube/config"
  }

}

provider "pihole" {
  url      = var.pi_hole_module.url
  password = var.pi_hole_module.password
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "default"
}
