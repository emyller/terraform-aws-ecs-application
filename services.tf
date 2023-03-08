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
      is_spot = alltrue(values(local.services)[*].is_spot)
      auto_scaling = {
        enabled = false
        min_instances = 1
        max_instances = 1  # Completely disable for grouped services
        cpu_threshold = 50
        memory_threshold = 50
      }
    }
  } : {
    # Each container to each service
    for item_name, service in local.services:
    item_name => {
      name = service.name
      family_name = "${local.common_name}-${service.name}"
      containers = { (item_name) = service }
      is_fargate = service.is_fargate
      is_spot = service.is_spot
      auto_scaling = service.auto_scaling
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
  execution_role_arn = aws_iam_role.execute.arn
  task_role_arn = aws_iam_role.task.arn

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

  # Create a volume to mount container files if any needs
  dynamic "volume" {
    for_each = anytrue([
      for service in values(each.value.containers):
      service.mount_files != null
    ]) ? [true] : []
    content {
      name = "file-mounter"
    }
  }

  dynamic volume {
    for_each = {
      for item in flatten([
        for container in values(each.value.containers): [
          for volume_name, volume in container.efs_mounts: {
            container_name = container.name
            volume_name = volume_name
            volume = volume
          }
        ]
      ]):
      ("${item.container_name}-${item.volume_name}") => item
    }
    content {
      name = volume.key

      efs_volume_configuration {
        file_system_id = volume.value.volume.file_system_id
        root_directory = volume.value.volume.root_directory
      }
    }
  }

  container_definitions = jsonencode(flatten([
    for item_name, service in each.value.containers: [
      {  # Main (essential) container
        image = "${local.docker_image_addresses[item_name]}:${service.docker.image_tag}"
        name = service.name
        essential = true
        command = service.command
        memoryReservation = service.memory
        links = [for link in coalesce(service.links, []): "${link}:${link}"]
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
            "awslogs-group" = aws_cloudwatch_log_group.main[var.group_logs ? "__all__" : item_name].name
            "awslogs-region" = data.aws_region.current.name
            "awslogs-stream-prefix" = "ecs"
          }
        }
        portMappings = [for port_map in [
          service.http == null ? null : {  # HTTP port, if any
            protocol = "tcp"
            containerPort = service.http.port
            hostPort = service.is_fargate ? service.http.port : 0
          },
          service.tcp == null ? null : {  # TCP port, if any
            protocol = "tcp"
            containerPort = coalesce(
              service.tcp.container_port,
              service.tcp.port,
            )
            hostPort = service.is_fargate ? coalesce(
              service.tcp.container_port,
              service.tcp.port,
            ) : 0
          },
        ]: port_map if port_map != null]

        healthCheck = service.health_check == null ? null : {
          command = service.health_check.command
          interval = service.health_check.interval
          timeout = service.health_check.timeout
          retries = service.health_check.retries
          startPeriod = service.health_check.start_period
        }

        dependsOn = concat(
          # Wait for file mounter
          service.mount_files == null ? [] : [{
            containerName = "file-mounter"
            condition = "COMPLETE"
          }],

          # Wait for explicit dependencies
          service.depends_on == null ? [] : [
            for name, state in service.depends_on: {
              containerName = name
              condition = state
            }
          ]
        )
        mountPoints = concat(
          service.mount_files == null ? [] : [  # Load mounted files, if any
            {
              containerPath = "/mnt"
              sourceVolume = "file-mounter"
            },
          ],
          [  # EFS mounts
            for volume_name, volume in service.efs_mounts:
            {
              containerPath = volume.mount_path
              sourceVolume = "${service.name}-${volume_name}"
            }
          ])
      },

      # Side container to create and mount files
      service.mount_files == null ? [] : [{
        image = "docker.io/bash:latest"
        name = "file-mounter"
        essential = false  # It will die after doing its job
        command = ["-c", join(";", formatlist(
          "echo '%s' | base64 -d - | tee /mnt/%s",
          values(service.mount_files),
          keys(service.mount_files),
        ))]
        mountPoints = [{  # Persist files to volume
          containerPath = "/mnt"
          sourceVolume = "file-mounter"
        }]
      }]
    ]
  ]))
}

resource "aws_ecs_service" "main" {
  for_each = local.grouped_services
  name = each.value.name
  cluster = data.aws_ecs_cluster.main.id
  task_definition = "${aws_ecs_task_definition.main[each.key].family}:${aws_ecs_task_definition.main[each.key].revision}"
  scheduling_strategy = "REPLICA"
  force_new_deployment = true
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent = 200
  enable_execute_command = true
  desired_count = each.value.auto_scaling.min_instances

  # Allow HTTP services to warm up before responding to health checks
  health_check_grace_period_seconds = (
    anytrue([for service in values(each.value.containers): service.http != null])
    ? max(180, compact([for service in values(each.value.containers): try(service.http.health_check.grace_period_seconds, 0)])...)
    : null  # No HTTP service
  )

  # Launch with EC2
  launch_type = each.value.is_fargate ? null : "EC2"

  # Launch with Fargate
  dynamic capacity_provider_strategy {
    for_each = each.value.is_fargate ? [true] : []
    content {
      capacity_provider = each.value.is_spot ? "FARGATE_SPOT" : "FARGATE"
      weight = 1
    }
  }

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
  
  # Associate tasks with a HTTP target group
  dynamic "load_balancer" {
    iterator = target_service
    for_each = {
      for service_name, service in each.value.containers:
      service_name => service
      if service.http != null
    }
    content {
      target_group_arn = aws_lb_target_group.http[target_service.key].arn
      container_name = target_service.value.name
      container_port = target_service.value.http.port
    }
  }

  # Associate tasks with a TCP target group
  dynamic "load_balancer" {
    iterator = target_service
    for_each = {
      for service_name, service in each.value.containers:
      service_name => service
      if service.tcp != null
    }
    content {
      target_group_arn = aws_lb_target_group.tcp[target_service.key].arn
      container_name = target_service.value.name
      container_port = coalesce(
        target_service.value.tcp.container_port,
        target_service.value.tcp.port,
      )
    }
  }

  lifecycle {
    ignore_changes = [
      desired_count,  # Auto scaling will handle it
    ]
  }
}
