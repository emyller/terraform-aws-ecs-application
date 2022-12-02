locals {
  # Filter services that expose a TCP (non-HTTP) port
  tcp_services = {
    for service_name, service in local.services:
    service_name => service
    if service.tcp != null
  }

  # Distinct TCP load balancers
  tcp_load_balancer_names = toset(
    values(local.tcp_services)[*].tcp.load_balancer_name,
  )
}

data "aws_lb" "tcp" {
  for_each = local.tcp_load_balancer_names
  name = each.key
}

resource "aws_lb_target_group" "tcp" {
  /*
  The Target Groups to contain tasks with TCP listeners
  */
  for_each = local.tcp_services
  vpc_id = local.vpc_id
  name = "${local.target_group_names[each.key]}-tcp"
  port = coalesce(
    each.value.tcp.container_port,
    each.value.tcp.port,
  )
  deregistration_delay = 30
  protocol = "TCP"
  target_type = each.value.is_fargate ? "ip" : "instance"
  preserve_client_ip = coalesce(each.value.tcp.preserve_client_ip, false)

  health_check {
    interval = 30
    unhealthy_threshold = 2
    healthy_threshold = 2
    protocol = "TCP"
    port = each.value.is_fargate ? coalesce(
      each.value.tcp.container_port,
      each.value.tcp.port,
    ) : "traffic-port"
  }
}

resource "aws_lb_listener" "tcp" {
  /*
  Open port in the NLB pointing to service
  */
  for_each = local.tcp_services
  load_balancer_arn = data.aws_lb.tcp[each.value.tcp.load_balancer_name].arn
  port = each.value.tcp.port
  protocol = "TCP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.tcp[each.key].arn
  }
}
