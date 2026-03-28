variable "github_pat" {
  type      = string
  sensitive = true
}

variable "runner_platforms" {
  type    = list(string)
  default = ["amd64", "arm64", "armv7"]
}
