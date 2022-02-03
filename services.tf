locals {
  # Map of service names to their ECR repository, if set
  ecr_image_names = {
    for service_name, service in var.services:
    service_name => service.docker.image_name
    if service.docker.source == "ecr"
  }
}

data "aws_ecr_repository" "services" {
  for_each = local.ecr_image_names
  name = each.value
}

data "aws_secretsmanager_secret" "services" {
  for_each = var.secrets
  name = each.value
}
