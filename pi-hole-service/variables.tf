variable "record" {
  type = string
}

variable "ingress" {
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