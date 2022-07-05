output "ingress" {
  value = kubernetes_ingress_v1.pihole_ingress
}

output "url" {
  value = "http://${kubernetes_service.pihole_api.status.0.load_balancer.0.ingress.0.ip}:8080/"
}

output "password" {
  value = random_password.password.result
}
