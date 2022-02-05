resource "aws_iam_role" "ecs_agent" {
  /*
  Role to be assumed by the ECS agent in each ECS instance

  This role needs permissions to:
  - Fetch Docker images from Elastic Container Registry (if set).
  - Fetch secrets from Secrets Manager and inject them in containers as
    environment variables (if any).
  */
  name = "ecs-${var.application_name}-${var.environment_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent_assume.json

  # Permission to fetch a Docker image from Elastic Container Registry
  dynamic "inline_policy" {
    for_each = length(local.ecr_image_names) > 0 ? [true] : []
    content {
      name = "pull-ecr-image"
      policy = data.aws_iam_policy_document.pull_ecr_image.json
    }
  }

  # Permission to fetch secrets from Secrets Manager
  dynamic "inline_policy" {
    for_each = length(var.secrets) > 0 ? [true] : []
    content {
      name = "get-secrets"
      policy = data.aws_iam_policy_document.get_secrets.json
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
  statement {
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      for service_name in keys(local.ecr_image_names):
      data.aws_ecr_repository.services[service_name].arn
    ]
  }
}

data "aws_iam_policy_document" "get_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      for env_var_name in keys(var.secrets):
      data.aws_secretsmanager_secret.services[env_var_name].arn
    ]
  }
}
