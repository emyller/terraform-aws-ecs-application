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
    })
  }

  scheduled_tasks = {
    for name, item in var.scheduled_tasks:
    "scheduled-tasks/${name}" => merge(item, {
      name = name
      full_name = "scheduled-tasks/${name}"
      is_fargate = item.launch_type == "FARGATE"
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
