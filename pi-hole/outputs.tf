output "url" {
  value = "http://${local.host}/"
}

output "password" {
  value = random_password.password.result
}
