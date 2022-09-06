terraform {
  experiments = [module_variable_optional_attrs]
}

data "aws_region" "current" {
}

data "aws_subnet" "any" {
  id = var.subnets[0]
}

locals {
  vpc_id = data.aws_subnet.any.vpc_id
  common_name = "${var.environment_name}-${var.application_name}"

  services = {
    for name, item in var.services:
    "services/${name}" => merge(item, {
      name = name
      full_name = "services/${name}"
      is_fargate = item.launch_type == "FARGATE"
      is_spot = coalesce(item.is_spot, false)
      desired_count = coalesce(
        item.desired_count,
        try(item.auto_scaling.min_instances, 1),
      )
      auto_scaling = {
        enabled = item.auto_scaling != null
        min_instances = try(item.auto_scaling.min_instances, 1)
        max_instances = try(item.auto_scaling.max_instances, 1)
        cpu_threshold = try(item.auto_scaling.cpu_threshold, 80)
        memory_threshold = try(item.auto_scaling.memory_threshold, 80)
      }
    })
  }

  scheduled_tasks = {
    for name, item in var.scheduled_tasks:
    "scheduled-tasks/${name}" => merge(item, {
      name = name
      full_name = "scheduled-tasks/${name}"
      is_fargate = item.launch_type == "FARGATE"
      is_spot = coalesce(item.is_spot, false)
    })
  }

  reactive_tasks = {
    for name, item in var.reactive_tasks:
    "reactive-tasks/${name}" => merge(item, {
      name = name
      full_name = "reactive-tasks/${name}"
      is_fargate = item.launch_type == "FARGATE"
    })
  }
  
  runnables = merge(local.services, local.scheduled_tasks, local.reactive_tasks)
}
