terraform {
  required_providers {
    pihole = {
      source = "ryanwholey/pihole"
    }
  }
}

# provider "pihole" {
#   url      = var.pi_hole_module.url
#   password = var.pi_hole_module.password
# }
