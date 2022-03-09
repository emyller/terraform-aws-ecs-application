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

  # Standard limit of rules per ALB listener
  rules_count_limit = 100

  # Distinct load balancers
  load_balancer_names = toset(values(local.http_services)[*].http.load_balancer_name)

  # Map of services to the load balancer listeners they will be bound to
  listener_arns = {
    for service_name, service in local.http_services:
    service_name => data.aws_lb_listener.https[service.http.load_balancer_name].arn
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
  deregistration_delay = 30
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
  for_each = local.http_services
  listener_arn = local.listener_arns[each.key]
  priority = random_integer.rule_priority[each.key].result

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.http[each.key].arn
  }

  # Match hostnames
  condition {
    host_header { values = each.value.http.listener_rule.hostnames }
  }

  # Match path patterns
  dynamic "condition" {
    for_each = each.value.http.listener_rule.paths == null ? [] : [true]
    content {
      path_pattern { values = each.value.http.listener_rule.paths }
    }
  }

  # Match HTTP headers
  dynamic "condition" {
    for_each = coalesce(each.value.http.listener_rule.headers, {})
    content {
      http_header {
        http_header_name = condition.key
        values = condition.value
      }
    }
  }

  # HTTP request methods
  dynamic "condition" {
    for_each = each.value.http.listener_rule.methods == null ? [] : [true]
    content {
      http_request_method { values = each.value.http.listener_rule.methods }
    }
  }
}

resource "random_integer" "rule_priority" {
  /*
  A number to manage the priority numbers to use in ALB rules without a path

  ALBv2 does not sort rules by specificity; rather, it sorts them by a priority
  number from 1 to 50000. Also, the default limit of rules per listener is 100.
  This resource manages a random number in the first 40000 positions for rules
  with paths, or in the remaining 10000 for rules without any path.

  More:
  https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-update-rules.html
  */
  for_each = {
    for service_name, service in local.http_services:
    service_name => merge(service, {
      priority_level = 4 - sum([
        service.http.listener_rule.hostnames == null ? 0 : 1,
        service.http.listener_rule.paths == null ? 0 : 1,
        service.http.listener_rule.headers == null ? 0 : 1,
        service.http.listener_rule.methods == null ? 0 : 1,
      ])
    })
  }
  min = each.value.priority_level * floor(50000 / 6)
  max = each.value.priority_level * floor(50000 / 6) + floor(50000 / 6)
  keepers = { listener_arn = data.aws_lb_listener.https[each.value.http.load_balancer_name].arn }
}
