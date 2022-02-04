locals {
  # Filter services that expose a HTTP port
  http_services = {
    for service_name, service in var.services:
    service_name => service
    if service.http != null
  }

  # Map service names to target group names
  target_group_names = {
    for service_name in keys(var.services):
    service_name => "${local.common_name}-${service_name}"
  }

  # Create a recursive product of service_name + hostname + path for ALB rules
  load_balancer_rules_combinations = {
    for rule in flatten([
      for service_name, service in local.http_services: [
        for combo in setproduct(
          [service_name],  # service_name
          service.http.hostnames,  # hostname
          coalesce(service.http.paths, ["*"]),  # path -- default to "*"
        ): {
          service_name = combo[0]
          hostname = combo[1]
          path = combo[2]
          load_balancer_name = local.http_services[combo[0]].http.load_balancer_name
        }
      ]
    ]): ("${rule.service_name}|${rule.hostname}|${rule.path}") => rule
  }

  # Split rule combinations in specific and generic (path = *) ones
  load_balancer_rules_combinations_with_path = [
    for rule in values(local.load_balancer_rules_combinations):
    rule if rule.path != "*"
  ]
  load_balancer_rules_combinations_without_path = [
    for rule in values(local.load_balancer_rules_combinations):
    rule if rule.path == "*"
  ]

  # Standard limit of rules per ALB listener
  rules_count_limit = 100

  # Distinct load balancers
  load_balancer_names = toset(values(local.http_services)[*].http.load_balancer_name)

  # Map of services to the load balancer listeners they will be bound to
  listener_arns = {
    for service_name, service in local.http_services:
    service_name => data.aws_lb_listener.https[service.http.load_balancer_name].arn
  }

  # Map of listener to a rule priority block start
  listener_rule_priority_blocks = {
    for lb_name in local.load_balancer_names:
    lb_name => (random_integer.rule_priority_block_start[lb_name].result * local.rules_count_limit)
  }
}

data "aws_lb" "main" {
  for_each = local.load_balancer_names
  name = each.key
}

data "aws_lb_listener" "https" {
  for_each = local.load_balancer_names
  load_balancer_arn = data.aws_lb.main[each.key].arn
  port = 443
}

resource "aws_lb_target_group" "http" {
  /*
  The Target Groups to contain EC2 instances in HTTP services
  */
  for_each = local.http_services
  vpc_id = local.vpc_id
  name = local.target_group_names[each.key]
  port = each.value.http.port
  protocol = "HTTP"
  target_type = "instance"

  health_check {
    interval = 30
    path = each.value.http.health_check.path
    unhealthy_threshold = 2
    healthy_threshold = 2
    port = "traffic-port"
    matcher = join(",", each.value.http.health_check.status_codes)
  }
}

resource "aws_lb_listener_rule" "main" {
  /*
  Rules for the load balancer listener
  */
  for_each = local.load_balancer_rules_combinations
  listener_arn = local.listener_arns[each.value.service_name]

  # Assign a priority according to specificity
  priority = sum([
    local.listener_rule_priority_blocks[each.value.load_balancer_name],
    (each.value.path == "*"
      ? local.rules_count_limit - index(local.load_balancer_rules_combinations_without_path, each.value)
      : index(local.load_balancer_rules_combinations_with_path, each.value)
    ),
  ])

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.http[each.value.service_name].arn
  }

  condition {
    host_header { values = [each.value.hostname] }
  }

  condition {
    path_pattern { values = [each.value.path] }
  }
}

resource "random_integer" "rule_priority_block_start" {
  /*
  A number to manage the priority numbers to use in ALB rules

  ALBv2 does not sort rules by specificity; rather, it sorts them by a priority
  number from 1 to 50000. Also, the default limit of rules per listener is 100.
  This resource manages a number multiple of 100 to serve as a block of
  available priorities to use in the load balancer rules, having the intention
  of keeping the most generic ones last.

  More: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-update-rules.html
  */
  for_each = local.load_balancer_names
  min = 0  # first block: 0-100
  max = 499  # last block: 49900-50000
  keepers = { listener_arn = data.aws_lb_listener.https[each.key].arn }
}
