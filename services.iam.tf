locals {
  # Map service names to IAM role names
  ecs_agent_iam_role_names = {
    for service_name in keys(local.services):
    service_name => "ecs-${local.common_name}-${service_name}"
  }
}

resource "aws_iam_role" "ecs_agent" {
  /*
  Role to be assumed by the ECS agent in each ECS instance

  This role needs permissions to:
  - Fetch Docker images from Elastic Container Registry (if set).
  - Fetch secrets from Secrets Manager and inject them in containers as
    environment variables (if any).
  */
  for_each = local.services
  name = local.ecs_agent_iam_role_names[each.key]
  assume_role_policy = data.aws_iam_policy_document.ecs_agent_assume.json

  # Permission to fetch a Docker image from Elastic Container Registry
  dynamic "inline_policy" {
    for_each = each.value.ecr_image_name != null ? [true] : []
    content {
      name = "pull-ecr-image"
      policy = data.aws_iam_policy_document.pull_ecr_image[each.key].json
    }
  }

  # Permission to fetch secrets from Secrets Manager
  dynamic "inline_policy" {
    for_each = try(length(each.value.secrets), 0) > 0 ? [true] : []
    content {
      name = "get-secrets"
      policy = data.aws_iam_policy_document.get_secrets[each.key].json
    }
  }
}

data "aws_iam_policy_document" "ecs_agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pull_ecr_image" {
  for_each = toset([
    for service_name, service in local.services:
    service_name if service.ecr_image_name != null
  ])

  statement {
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [data.aws_ecr_repository.services[each.key].arn]
  }
}

data "aws_iam_policy_document" "get_secrets" {
  for_each = toset([
    for service_name, service in local.services:
    service_name if service.secrets != null
  ])

  statement {
    effect = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = values(local.services[each.key].secrets)  # ARNs only
  }
}
