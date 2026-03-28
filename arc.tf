variable "github_pat" {
  type      = string
  sensitive = true
}

module "arc" {
  source     = "./arc"
  github_pat = var.github_pat
}
