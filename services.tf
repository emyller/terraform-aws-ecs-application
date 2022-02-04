locals {
  # Map of service names to their ECR repository, if set
  ecr_image_names = {
    for service_name, service in var.services:
    service_name => service.docker.image_name
    if service.docker.source == "ecr"
  }

  # Map of service name to their Docker image address
  docker_image_addresses = {
    for service_name, service in var.services:
    service_name => {
      "dockerhub" = "docker.io/${service.docker.image_name}"
      "ecr" = try(data.aws_ecr_repository.services[service_name].repository_url, null)
    }[service.docker.source]
  }

  # Group containers if asked
  # Organize
  # GROUPED: { group_name: { service1, service2, service3, ... }
  # NORMAL: { service1: { service1 }, service2: { service2 }, ... }
  grouped_services = (var.group_containers ? {
    # All containers grouped in one service
    (local.common_name) = {
      family_name = local.common_name
      containers = var.services
    }
  } : {
    # Each container to each service
    for service_name, service in var.services:
    (service_name) => {
      family_name = "${local.common_name}-${service_name}"
      containers = { (service_name) = service }
    }
  })
}

data "aws_ecs_cluster" "main" {
  cluster_name = var.cluster_name
}

data "aws_ecr_repository" "services" {
  for_each = local.ecr_image_names
  name = each.value
}

data "aws_secretsmanager_secret" "services" {
  for_each = var.secrets
  name = each.value
}

resource "aws_ecs_task_definition" "main" {
  /*
  A task definition for each service in the application
  */
  for_each = local.grouped_services
  family = each.value.family_name
  network_mode = "bridge"
  execution_role_arn = aws_iam_role.ecs_agent.arn

  container_definitions = jsonencode([
    for service_name, service in each.value.containers:
    merge({
      image = "${local.docker_image_addresses[service_name]}:${service.docker.image_tag}"
      name = service_name
      essential = true
      memoryReservation = service.memory
      environment = [
        for env_var_name, value in var.environment_variables:
        { name = env_var_name, value = value }
      ]
      secrets = [
        for env_var_name, secret_name in var.secrets:
        { name = env_var_name, valueFrom = data.aws_secretsmanager_secret.services[env_var_name].arn }
      ]
    },

    # Publish ports only if intended
    service.http == null ? {} : {
      portMappings = [{
        protocol = "tcp"
        containerPort = service.http.port
        hostPort = 0  # Dynamic port
      }]
    },

    # Link containers to each other
    # https://docs.docker.com/network/links/
    !var.group_containers ? {} : {
      links = [
        for other_service_name in setsubtract(keys(each.value), [service_name]):
        "${other_service_name}:${other_service_name}"
      ]
    },

    # Append a command only if it's set
    service.command == null ? {} : {
      command = service.command
    })
  ])
}

resource "aws_ecs_service" "main" {
  for_each = local.grouped_services
  name = each.key
  cluster = data.aws_ecs_cluster.main.id
  task_definition = "${aws_ecs_task_definition.main[each.key].family}:${aws_ecs_task_definition.main[each.key].revision}"
  launch_type = "EC2"
  scheduling_strategy = "REPLICA"
  force_new_deployment = true
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200

  # When grouping containers in a single service, desired count needs to be 1
  desired_count = var.group_containers ? 1 : one(values(each.value.containers)).desired_count

  # Allow HTTP services to warm up before responding to health checks
  health_check_grace_period_seconds = (
    anytrue([for service in values(each.value.containers): service.http != null])
    ? max(180, compact([for service in values(each.value.containers): try(service.http.health_check.grace_period_seconds, 0)])...)
    : null  # No HTTP service
  )

  ordered_placement_strategy {
    type = "spread"
    field = "attribute:ecs.availability-zone"
  }

  dynamic "load_balancer" {
    iterator = target_service
    for_each = {
      for service_name, service in each.value.containers:
      service_name => service
      if service.http != null
    }
    content {
      target_group_arn = aws_lb_target_group.http[target_service.key].arn
      container_name = target_service.key
      container_port = target_service.value.http.port
    }
  }
}
