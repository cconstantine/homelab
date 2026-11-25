provider "github" {
  owner = "cconstantine"
  token = var.github_pat
}

module "github" {
  source = "./github"
}

import {
  to = module.github.github_repository.smelt
  id = "smelt"
}
