resource "github_repository" "homelab" {
  name        = "homelab"
  description = ""

  visibility = "public"
  auto_init = true
}

resource "github_branch" "master" {
  repository = github_repository.homelab.name
  branch     = "master"
}

resource "github_branch_default" "default"{
  repository = github_repository.homelab.name
  branch     = github_branch.master.branch
}