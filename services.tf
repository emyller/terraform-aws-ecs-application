locals {
  # Recollect services with required adjustments
  services = {
    for service_name, service in var.services:
    service_name => merge(service, {
      desired_count = coalesce(service.desired_count, 1)
      task_definition_name = "${var.cluster_name}-${service_name}"
      target_group_name = "${var.cluster_name}-${service_name}"
      http = try(merge(service.http, {
        paths = coalesce(service.http.paths, ["*"])
      }), null)
    })
  }
}
