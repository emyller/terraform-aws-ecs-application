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

variable "security_group_ids" {
  description = "Security groups to assign to Fargate tasks, if any."
  type = list(string)
  default = []
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

variable "group_logs" {
  description = "Whether to group all logs into a single log group."
  type = bool
  default = false
}

variable "log_retention_days" {
  description = "Amount of days to store log history."
  type = number
  default = 14
}

variable "services" {
  description = "A mapping of services to deploy in the cluster."
  type = map(object({
    desired_count = optional(number)
    memory = number
    cpu_units = optional(number)
    launch_type = optional(string)
    is_spot = optional(bool)
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
        methods = optional(list(string))
        query_string = optional(map(string))
        source_ips = optional(list(string))
      })
      health_check = object({
        path = string,
        status_codes = list(number)
        grace_period_seconds = optional(number)
      })
    }))
    tcp = optional(object({
      port = number
      container_port = optional(number)
      load_balancer_name = string
    }))
    placement_strategy = optional(object({
      type = string
      field = string
    }))
    mount_files = optional(map(string))
    efs_mounts = optional(map(object({
      file_system_id = string
      root_directory = string
      mount_path = string
    })))
    auto_scaling = optional(object({
      min_instances = number
      max_instances = number
      cpu_threshold = optional(number)
      memory_threshold = optional(number)
    }))
  }))

  validation {
    condition = length(setsubtract(
      values(var.services)[*].docker.source,
      ["dockerhub", "ecr"],
    )) == 0
    error_message = "The 'var.services[*].docker.source' must be one of: [dockerhub, ecr]."
  }

  default = {}
}

variable "scheduled_tasks" {
  description = "A mapping of scheduled tasks to deploy in the cluster."
  type = map(object({
    schedule_expression = string
    memory = number
    cpu_units = optional(number)
    launch_type = optional(string)
    command = optional(list(string))
    environment = optional(map(string))
    secrets = optional(map(string))
    docker = object({
      image_name = string
      image_tag = string
      source = string
    })
  }))

  validation {
    condition = length(setsubtract(
      values(var.scheduled_tasks)[*].docker.source,
      ["dockerhub", "ecr"],
    )) == 0
    error_message = "The 'var.services[*].docker.source' must be one of: [dockerhub, ecr]."
  }

  default = {}
}

variable "reactive_tasks" {
  description = "A mapping of reactive tasks to deploy in the cluster."
  type = map(object({
    memory = number
    cpu_units = optional(number)
    launch_type = optional(string)
    command = optional(list(string))
    environment = optional(map(string))
    secrets = optional(map(string))
    docker = object({
      image_name = string
      image_tag = string
      source = string
    })
    event_pattern = object({
      source = list(string)
      detail_type = list(string)
      detail = any  # Format defined by AWS API
    })
    event_variables = map(string)
  }))

  validation {
    condition = length(setsubtract(
      values(var.reactive_tasks)[*].docker.source,
      ["dockerhub", "ecr"],
    )) == 0
    error_message = "The 'var.services[*].docker.source' must be one of: [dockerhub, ecr]."
  }

  default = {}
}
