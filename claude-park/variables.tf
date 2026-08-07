variable "node_ips" {
  description = "IPs of the k3s nodes that host parks (homelab: control-plane, secondary; ryzen: primary worker). Covered by the docker daemon server cert's SANs so the Mac can dial either node."
  type        = list(string)
  default     = ["192.168.8.130", "192.168.8.217"]
}

variable "api_server_ip" {
  description = "k3s control-plane IP the emitted kubeconfig points at. Must be in the API server certificate's SANs."
  type        = string
  default     = "192.168.8.130"
}

