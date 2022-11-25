resource "aws_iam_role" "event_dispatcher" {
  name = "ecs-events-${var.environment_name}-${var.application_name}"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "event_dispatch" {
  count = ((length(local.scheduled_tasks) + length(local.reactive_tasks)) > 0) ? 1 : 0
  name = "event-dispatch"
  policy = data.aws_iam_policy_document.event_dispatch.json
  role = aws_iam_role.event_dispatcher.id
}

data "aws_iam_policy_document" "event_dispatch" {
  # Allow EventBridge to run a task
  statement {
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${local.common_name}",  # Grouped services
      "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${local.common_name}-*",  # Separated services
    ]
  }

  # Let EventBridge pass assign an IAM role to the task
  statement {
    actions = ["iam:PassRole"]
    resources = [aws_iam_role.execute.arn]
  }
}
