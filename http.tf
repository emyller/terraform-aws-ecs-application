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

  Mapped by a product of services + hostnames + paths, e.g:
  {
    "service1-example.com-*": {
      service_name = "service1", hostname = "example.com", path = "*"
    },
    "service1-example.com-/foo": {
      service_name = "service1", hostname = "example.com", path = "/foo"
    },
  }

  TODO: manage order with rule priority
  */
  for_each = {
    for rule in flatten([
      for service_name, service in local.http_services: [
        for combo in setproduct(
          [service_name],
          service.http.hostnames,
          coalesce(service.http.paths, ["*"]),  # Default to * (any path)
        ):
        zipmap(["service_name", "hostname", "path"], combo)
      ]
    ]): ("${rule.service_name}-${rule.hostname}-${rule.path}") => rule
  }

  listener_arn = local.http_services[each.value.service_name].http.listener_arn

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
