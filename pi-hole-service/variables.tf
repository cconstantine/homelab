variable "record" {
  type = string
}

variable "ip" {
  default = null
  type = string
}

variable "ingress" {
  default = null
  type = object({
    status = list(
      object({
        load_balancer = list(
          object({
            ingress = list(
              object({
                ip       = string,
                hostname = string
            }))
          })
        )
      })
    )
  })
}