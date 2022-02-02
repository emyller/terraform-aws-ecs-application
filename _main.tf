terraform {
  experiments = [module_variable_optional_attrs]
}

data "aws_subnet" "any" {
  id = var.subnets[0]
}

locals {
  vpc_id = data.aws_subnet.any.vpc_id
  common_name = var.cluster_name  # Common name to use in most objects
}
