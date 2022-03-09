variable "application_name" {
  description = "The name of the application."
  type = string
}

variable "environment_name" {
  description = "The name of the environment."
  type = string
}

variable "cluster_name" {
  description = "The name of the cluster to plug this application in."
  type = string
}

variable "subnets" {
  description = "The subnets to place objects in."
  type = list(string)
}

variable "environment_variables" {
  description = <<-EOT
    A map of environment variables to inject in the containers.
    Environment variables set in services override this setting.
  EOT
  type = map(string)
  default = {}
}

variable "secrets" {
  description = <<-EOT
    A map of secrets to inject in the containers as environment variables.
    Secrets set in services override this setting.
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
    environment = optional(map(string))
    secrets = optional(map(string))
    links = optional(list(string))
    docker = object({
      image_name = string
      image_tag = string
      source = string
    })
    http = optional(object({
      port = number
      load_balancer_name = string
      listener_rule = object({
        hostnames = list(string)
        paths = optional(list(string))
        headers = optional(map(list(string)))
        # methods = optional(list(string))
        # query_string = optional(map(string))
        # source_ips = optional(list(string))
      })
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
