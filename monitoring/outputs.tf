output "public_services" {
  value = {
    "prometheus.${var.domain}" = kubernetes_ingress.prometheus_ingress,
    "grafana.${var.domain}" = kubernetes_ingress.grafana_ingress
    }
}

output "grafana_ingress" {
  value = kubernetes_ingress.grafana_ingress
}