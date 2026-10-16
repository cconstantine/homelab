variable "github_pat" {
  type      = string
  sensitive = true
}

variable "github_pat_smelt" {
  type      = string
  sensitive = true
}

module "arc" {
  source           = "./arc"
  github_pat       = var.github_pat
  github_pat_smelt = var.github_pat_smelt
}
