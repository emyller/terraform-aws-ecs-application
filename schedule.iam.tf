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
  name = "event-dispatch"
  policy = data.aws_iam_policy_document.event_dispatch.json
  role = aws_iam_role.event_dispatcher.id
}

data "aws_iam_policy_document" "event_dispatch" {
  statement {
    actions = [
      "ecs:RunTask",
    ]
    resources = [
      for task_name in keys(var.scheduled_tasks):
      "${aws_ecs_task_definition.scheduled_task[task_name].arn}:*"
    ]
  }
  statement {
    actions = [
      "iam:PassRole",
    ]
    resources = ["*"]
  }
}
