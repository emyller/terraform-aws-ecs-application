locals {
  # Group containers if asked
  # Organize
  # GROUPED: { group_name: { service1, service2, service3, ... }
  # NORMAL: { service1: { service1 }, service2: { service2 }, ... }
  grouped_services = (var.group_containers ? {
    # All containers grouped in one service
    (var.application_name) = {
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
        for env_var_name, value in coalesce(service.environment, var.environment_variables):
        { name = env_var_name, value = value }
      ]
      secrets = [
        for service_secret, secret_info in local.service_secrets[service_name]: {
          name = secret_info.env_var_name,
          valueFrom = data.aws_secretsmanager_secret.services[service_secret].arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" = aws_cloudwatch_log_group.main[service_name].name
          "awslogs-region" = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },

    # Publish ports only if intended
    service.http == null ? {} : {
      portMappings = [{
        protocol = "tcp"
        containerPort = service.http.port
        hostPort = 0  # Dynamic port
      }]
    },

    # Link containers to others they need
    # https://docs.docker.com/network/links/
    service.links == null ? {} : {
      links = [for link in service.links: "${link}:${link}"]
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

  # Place tasks according to available memory when grouping containers. Since
  # container grouping is intented for non-production use, there is no point in
  # spreading tasks.
  dynamic "ordered_placement_strategy" {
    for_each = var.group_containers ? [true] : []
    content {
      type = "binpack"
      field = "memory"
    }
  }

  # Place tasks according to service configuration. Historical default value is
  # "spread(attribute:ecs.availability-zone)", may incur extra costs.
  dynamic "ordered_placement_strategy" {
    for_each = var.group_containers ? [] : [true]
    content {
      type = try(each.value.containers[each.key].placement_strategy.type, "spread")
      field = try(each.value.containers[each.key].placement_strategy.field, "attribute:ecs.availability-zone")
    }
  }
  
  ordered_placement_strategy {
    type = var.group_containers ? "binpack" : try(
      each.value.containers[each.key].placement_strategy.type,
      "spread",  # Historical default value, may incur extra costs
    )
    field = var.group_containers ? "memory" : try(
      each.value.containers[each.key].placement_strategy.field,
      "attribute:ecs.availability-zone",
    )
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
