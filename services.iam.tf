resource "aws_iam_role" "ecs_agent" {
  /*
  Role to be assumed by the ECS agent in each ECS instance

  This role needs permissions to:
  - Fetch Docker images from Elastic Container Registry (if set).
  - Fetch secrets from Secrets Manager and inject them in containers as
    environment variables (if any).
  */
  name = "ecs-${var.environment_name}-${var.application_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent_assume.json
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
