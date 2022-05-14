terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.4.1"
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
