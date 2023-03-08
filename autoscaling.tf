resource "aws_appautoscaling_target" "main" {
  /*
  Auto scaling target for the ECS services
  */
  depends_on = [aws_ecs_service.main]
  for_each = local.grouped_services

  resource_id = "service/${var.cluster_name}/${each.value.name}"
  min_capacity = each.value.auto_scaling.min_instances
  max_capacity = each.value.auto_scaling.max_instances
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  /*
  Scale services based on CPU use
  */
  depends_on = [aws_ecs_service.main]
  for_each = {
    for name, service in local.grouped_services:
    (name) => service
    if service.auto_scaling.cpu_threshold != null
  }

  name = "cpu"
  policy_type = "TargetTrackingScaling"
  resource_id = aws_appautoscaling_target.main[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  service_namespace = aws_appautoscaling_target.main[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = each.value.auto_scaling.cpu_threshold

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  /*
  Scale services based memory use
  */
  for_each = {
    for name, service in local.grouped_services:
    (name) => service
    if service.auto_scaling.memory_threshold != null
  }

  name = "memory"
  policy_type = "TargetTrackingScaling"
  resource_id = aws_appautoscaling_target.main[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  service_namespace = aws_appautoscaling_target.main[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = each.value.auto_scaling.memory_threshold

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

resource "aws_appautoscaling_scheduled_action" "shutdown" {
  /*
  Scheduled shutdown of services
  */
  for_each = (var.scheduled_shutdown != null ? local.grouped_services : {})

  name = "ecs"
  service_namespace = aws_appautoscaling_target.main[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.main[each.key].scalable_dimension
  resource_id = aws_appautoscaling_target.main[each.key].resource_id
  schedule = var.scheduled_shutdown

  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}
