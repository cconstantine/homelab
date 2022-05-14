output "public_services" {
  value = [
    "prometheus.${var.domain}",
    "grafana.${var.domain}"
    ]
}