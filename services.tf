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
      "ecr" = try(data.aws_ecr_repository.services[service_name].repository_url, null)
    }[service.docker.source]
  }
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
  for_each = var.services
  family = "${local.common_name}-${each.key}"
  network_mode = "bridge"
  execution_role_arn = aws_iam_role.ecs_agent.arn

  container_definitions = jsonencode([
    merge({
      image = "${local.docker_image_addresses[each.key]}:${each.value.docker.image_tag}"
      name = each.key
      essential = true
      memoryReservation = each.value.memory
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
    each.value.http == null ? {} : {
      portMappings = [{
        protocol = "tcp"
        containerPort = each.value.http.port
        hostPort = 0  # Dynamic port
      }]
    },

    # Append a command only if it's set
    each.value.command == null ? {} : {
      command = each.value.command
    })
  ])
}

resource "aws_ecs_service" "main" {
  for_each = var.services
  name = "${local.common_name}-${each.key}"
  cluster = data.aws_ecs_cluster.main.id
  task_definition = "${aws_ecs_task_definition.main[each.key].family}:${aws_ecs_task_definition.main[each.key].revision}"
  desired_count = each.value.desired_count
  launch_type = "EC2"
  scheduling_strategy = "REPLICA"
  force_new_deployment = true
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200

  # Allow HTTP services to warm up before responding to health checks
  health_check_grace_period_seconds = try(
    coalesce(each.value.http.health_check.grace_period_seconds, 180),
    null,
  )

  ordered_placement_strategy {
    type = "spread"
    field = "attribute:ecs.availability-zone"
  }

  dynamic "load_balancer" {
    for_each = each.value.http == null ? [] : [true]
    content {
      target_group_arn = aws_lb_target_group.http[each.key].arn
      container_name = each.key
      container_port = each.value.http.port
    }
  }
}
