resource "aws_iam_role" "execute" {
  /*
  Role to be assumed by the ECS task
  */
  name = "ecs-${var.environment_name}-${var.application_name}"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

data "aws_iam_policy_document" "task_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  /*
  Role to be assumed by the task at container level

  This role needs permissions to:
  - Use SSM to enable ECS Exec commands, e.g. ssh to containers
  */
  name = "ecs-${var.environment_name}-${var.application_name}-task"
  assume_role_policy = data.aws_iam_policy_document.task_assume.json
}

resource "aws_iam_role_policy" "task_exec" {
  name = "ecs-exec"
  role = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_exec.json
}

data "aws_iam_policy_document" "task_exec" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"] 
  }
}
