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

resource "aws_iam_role" "ecs_task" {
  /*
  Role to be assumed by the task at container level

  This role needs permissions to:
  - Use SSM to enable ECS Exec commands, e.g. ssh to containers
  */
  name = "ecs-${var.environment_name}-${var.application_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent_assume.json
}

resource "aws_iam_role_policy" "ecs_task_exec" {
  name = "ecs-exec"
  role = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task_exec.json
}

data "aws_iam_policy_document" "ecs_task_exec" {
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
