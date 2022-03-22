locals {
  # Each container to each scheduled task
  scheduled_tasks = {
    for task_name, task in var.scheduled_tasks:
      (task_name) => {
        family_name = "${local.common_name}-${task_name}"
        containers = { (task_name) = task }
      }
  }
}

resource "aws_ecs_task_definition" "scheduled_task" {
  /*
  A task definition for each scheduled task
  */
  for_each = local.scheduled_tasks
  family = each.value.family_name
  execution_role_arn = aws_iam_role.ecs_agent.arn

  container_definitions = jsonencode([
    for task_name, task in each.value.containers:
    merge({
      image = "${local.docker_image_addresses[task_name]}:${task.docker.image_tag}"
      name = task_name
      essential = true
      memoryReservation = task.memory
      environment = [
        for env_var_name, value in coalesce(task.environment, var.environment_variables):
        { name = env_var_name, value = value }
      ]
      secrets = [
        for task_secret, secret_info in local.service_secrets[task_name]: {
          name = secret_info.env_var_name,
          valueFrom = data.aws_secretsmanager_secret.services[task_secret].arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" = aws_cloudwatch_log_group.main[task_name].name
          "awslogs-region" = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    
    # Append a command only if it's set
    task.command == null ? {} : {
      command = task.command
    })
  ])
}

resource "aws_cloudwatch_event_rule" "event_rule" {
  for_each = var.scheduled_tasks
  name = each.key
  schedule_expression = each.value.schedule_expression
}

resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {
  for_each = var.scheduled_tasks
  rule = aws_cloudwatch_event_rule.event_rule[each.key].name
  arn = data.aws_ecs_cluster.main.arn
  role_arn = aws_iam_role.event_dispatcher.arn

  ecs_target {
    launch_type = "EC2"
    task_count = 1
    task_definition_arn = aws_ecs_task_definition.scheduled_task[each.key].arn
  }
}
