resource "aws_ecs_task_definition" "scheduled_tasks" {
  /*
  A task definition for each scheduled task
  */
  for_each = local.scheduled_tasks
  family = "${local.common_name}-${each.value.name}"
  execution_role_arn = aws_iam_role.execute.arn

  # Set requirement if using Fargate
  requires_compatibilities = each.value.is_fargate ? ["FARGATE"] : null

  # Fargate requires setting CPU units
  cpu = each.value.is_fargate ? coalesce(each.value.cpu_units, 256) : null

  # Fargate needs memory to be set at task level
  memory = each.value.is_fargate ? each.value.memory : null

  # Fargate only supports VPC networking
  network_mode = each.value.is_fargate ? "awsvpc" : null

  # Fargate requires setting a runtime platform
  dynamic "runtime_platform" {
    for_each = each.value.is_fargate ? [true] : []
    content {
      operating_system_family = "LINUX"
      cpu_architecture = "X86_64"  # TODO: Think about supporting ARM64
    }
  }

  container_definitions = jsonencode([
    merge({
      image = "${local.docker_image_addresses[each.key]}:${each.value.docker.image_tag}"
      name = each.value.name
      essential = true
      memoryReservation = each.value.memory
      environment = [
        for env_var_name, value in coalesce(each.value.environment, var.environment_variables):
        { name = env_var_name, value = value }
      ]
      secrets = [
        for task_secret, secret_info in local.service_secrets[each.key]: {
          name = secret_info.env_var_name,
          valueFrom = data.aws_secretsmanager_secret.services[task_secret].arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" = aws_cloudwatch_log_group.main[var.group_logs ? "__all__" : each.key].name
          "awslogs-region" = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    
    # Append a command only if it's set
    each.value.command == null ? {} : {
      command = each.value.command
    })
  ])
}

resource "aws_cloudwatch_event_rule" "event_rule" {
  for_each = local.scheduled_tasks
  name = each.value.name
  schedule_expression = each.value.schedule_expression
}

resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {
  for_each = local.scheduled_tasks
  rule = aws_cloudwatch_event_rule.event_rule[each.key].name
  arn = data.aws_ecs_cluster.main.arn
  role_arn = aws_iam_role.event_dispatcher.arn

  ecs_target {
    launch_type = coalesce(each.value.launch_type, "EC2")
    task_count = 1
    task_definition_arn = aws_ecs_task_definition.scheduled_tasks[each.key].arn

    # Fargate tasks need explicit network configuration
    dynamic "network_configuration" {
      for_each = each.value.is_fargate ? [true] : []
      content {
        subnets = var.subnets
        security_groups = var.security_group_ids
        assign_public_ip = false
      }
    }
  }
}
