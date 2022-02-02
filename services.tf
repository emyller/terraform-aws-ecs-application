locals {
  # Recollect services with required adjustments
  services = {
    for service_name, service in var.services:
    service_name => merge(service, {
      desired_count = coalesce(service.desired_count, 1)
      http = try(merge(service.http, {
        paths = coalesce(service.http.paths, ["*"])
      }), null)
    })
  }

  # Map of service names to their ECR repository, if set
  ecr_image_names = {
    for service_name, service in local.services:
    service_name => service.ecr_image_name
    if service.ecr_image_name != null  # Not all services use ECR
  }
}

data "aws_ecr_repository" "services" {
  for_each = local.ecr_image_names
  name = each.value
}
