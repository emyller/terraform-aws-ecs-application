resource "aws_iam_role" "tasks" {
  /*
  Role to be assumed by the ECS task
  */
  name = "ecs-${var.environment_name}-${var.application_name}"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
}

data "aws_iam_policy_document" "tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
