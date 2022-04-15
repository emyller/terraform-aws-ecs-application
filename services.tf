locals {
  # Group containers if asked
  # Organize
  # GROUPED: { group_name: { service1, service2, service3, ... }
  # NORMAL: { service1: { service1 }, service2: { service2 }, ... }
  grouped_services = (var.group_containers ? {
    # All containers grouped in one service
    (var.application_name) = {
      name = var.application_name
      family_name = local.common_name
      containers = local.services
      is_fargate = one(distinct([
        for container in values(local.services):
        coalesce(container.launch_type, "EC2")
      ])) == "FARGATE"
    }
  } : {
    # Each container to each service
    for item_name, service in local.services:
    item_name => {
      name = service.name
      family_name = "${local.common_name}-${service.name}"
      containers = { (item_name) = service }
      is_fargate = service.is_fargate
    }
  })
}

data "aws_ecs_cluster" "main" {
  cluster_name = var.cluster_name
}

resource "aws_ecs_task_definition" "main" {  # TODO: Rename to "services"
  /*
  A task definition for each service in the application
  */
  for_each = local.grouped_services
  family = each.value.family_name
  execution_role_arn = aws_iam_role.ecs_agent.arn
  task_role_arn = aws_iam_role.ecs_task.arn

  # Set requirement if using Fargate
  requires_compatibilities = each.value.is_fargate ? ["FARGATE"] : null

  # Fargate requires setting CPU units
  cpu = each.value.is_fargate ? sum([
    for container in each.value.containers:
    coalesce(container.cpu_units, 256)
  ]) : null

  # Fargate needs memory to be set at task level
  # memory = each.value.is_fargate ? sum(each.value.containers[*].memory) : null
  memory = each.value.is_fargate ? sum([
    for container in each.value.containers: container.memory
  ]) : null

  # Fargate only supports VPC networking
  network_mode = each.value.is_fargate ? "awsvpc" : "bridge"

  # Fargate requires setting a runtime platform
  dynamic "runtime_platform" {
    for_each = each.value.is_fargate ? [true] : []
    content {
      operating_system_family = "LINUX"
      cpu_architecture = "X86_64"  # TODO: Think about supporting ARM64
    }
  }

  container_definitions = jsonencode([
    for item_name, service in each.value.containers:
    merge({
      image = "${local.docker_image_addresses[item_name]}:${service.docker.image_tag}"
      name = service.name
      essential = true
      memoryReservation = service.memory
      environment = [
        for env_var_name, value in coalesce(service.environment, var.environment_variables):
        { name = env_var_name, value = value }
      ]
      secrets = [
        for service_secret, secret_info in local.service_secrets[item_name]: {
          name = secret_info.env_var_name,
          valueFrom = data.aws_secretsmanager_secret.services[service_secret].arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" = aws_cloudwatch_log_group.main[item_name].name
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
  name = each.value.name
  cluster = data.aws_ecs_cluster.main.id
  task_definition = "${aws_ecs_task_definition.main[each.key].family}:${aws_ecs_task_definition.main[each.key].revision}"
  launch_type = each.value.is_fargate ? "FARGATE" : "EC2"
  scheduling_strategy = "REPLICA"
  force_new_deployment = true
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200
  enable_execute_command = true

  # When grouping containers in a single service, desired count needs to be 1
  desired_count = var.group_containers ? 1 : one(values(each.value.containers)).desired_count

  # Allow HTTP services to warm up before responding to health checks
  health_check_grace_period_seconds = (
    anytrue([for service in values(each.value.containers): service.http != null])
    ? max(180, compact([for service in values(each.value.containers): try(service.http.health_check.grace_period_seconds, 0)])...)
    : null  # No HTTP service
  )

  dynamic "network_configuration" {
    for_each = each.value.is_fargate ? [true] : []
    content {
      subnets = var.subnets
      security_groups = var.security_group_ids
      assign_public_ip = false
    }
  }

  # Place tasks according to available memory when grouping containers. Since
  # container grouping is intented for non-production use, there is no point in
  # spreading tasks.
  dynamic "ordered_placement_strategy" {
    for_each = (!each.value.is_fargate && var.group_containers) ? [true] : []
    content {
      type = "binpack"
      field = "memory"
    }
  }

  # Place tasks according to service configuration. Historical default value is
  # "spread(attribute:ecs.availability-zone)", may incur extra costs.
  dynamic "ordered_placement_strategy" {
    for_each = (each.value.is_fargate || var.group_containers) ? [] : [true]
    content {
      type = try(each.value.containers[each.key].placement_strategy.type, "spread")
      field = try(each.value.containers[each.key].placement_strategy.field, "attribute:ecs.availability-zone")
    }
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
