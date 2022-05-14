variable "pi_hole_module" {
  type = object({
    url      = string
    password = string
  })
}

variable "record" {
  type = string
}

variable "ip" {
  type = string
}

# variable "services" {
#   type = map(object({
#     status = list(
#         object({
#           load_balancer = list(
#             object({
#               ingress = list(
#                 object({
#                   ip       = string,
#                   hostname = string
#               }))
#             })
#           )
#         })
#       )
#     })
#   )
# }

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