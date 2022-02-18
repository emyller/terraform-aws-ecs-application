terraform {
  experiments = [module_variable_optional_attrs]
}

data "aws_region" "current" {
}

data "aws_subnet" "any" {
  id = var.subnets[0]
}

locals {
  vpc_id = data.aws_subnet.any.vpc_id
  common_name = "${var.environment_name}-${var.application_name}"
}
