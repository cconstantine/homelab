terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.4.1"
    }
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
  }
}