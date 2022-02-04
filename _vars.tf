variable "cluster_name" {
  description = "The name of the cluster to plug this application in."
  type = string
}

variable "subnets" {
  description = "The subnets to place objects in."
  type = list(string)
}

variable "environment_variables" {
  description = "A map of environment variables to inject in the containers."
  type = map(string)
  default = {}
}

variable "secrets" {
  description = <<-EOT
    A map of secrets to inject in the containers as environment variables.
    e.g. {"VARIABLE" = "secret-name"}
  EOT
  type = map(string)
  default = {}
}

variable "group_containers" {
  description = <<-EOT
    Whether to group all containers into a single service in ECS.
    This implicitly sets desired_count to 1 globally.
    Useful for non-production or test environments.
  EOT
  type = bool
  default = false
}

variable "services" {
  description = "A mapping of services to deploy in the cluster."
  type = map(object({
    desired_count = number
    memory = number
    command = optional(list(string))
    docker = object({
      image_name = string
      image_tag = string
      source = string
    })
    http = optional(object({
      hostnames = list(string)
      paths = optional(list(string))
      port = number
      load_balancer_name = string
      health_check = object({
        path = string,
        status_codes = list(number)
        grace_period_seconds = optional(number)
      })
    }))
  }))

  validation {
    condition = length(setsubtract(
      values(var.services)[*].docker.source,
      ["dockerhub", "ecr"],
    )) == 0
    error_message = "The 'var.services[*].docker.source' must be one of: [dockerhub, ecr]."
  }
}
