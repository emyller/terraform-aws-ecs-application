variable "cluster_name" {
  description = "The name of the cluster to plug this application in."
  type = string
}

variable "subnets" {
  description = "The subnets to place objects in."
  type = list(string)
}

variable "instance_type" {
  description = "The instance type of the EC2 hosts to spin up."
  type = string
}

variable "instance_key_name" {
  description = "The SSH key name in EC2 to manually connect to hosts."
  type = string
}

variable "environment_variables" {
  description = "A map of environment variables to inject in the containers."
  type = map(string)
  default = {}
}

variable "secrets" {
  description = <<EOT
    A map of secrets to inject in the containers as environment variables.
    e.g. {"VARIABLE" = "arn:aws:secretsmanager:..."}
  EOT
  type = map(string)
  default = {}
}

variable "services" {
  description = "A mapping of services to deploy in the cluster."
  type = map(object({
    ecr_image_name = string
    docker_image_tag = string
    desired_count = number
    memory = number
    command = optional(list(string))
    http = optional(object({
      hostnames = list(string)
      paths = optional(list(string))
      port = number
      listener_arn = string
      health_check = object({ path = string, status_codes = list(number) })
    }))
  }))
}
