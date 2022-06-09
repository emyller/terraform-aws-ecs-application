locals {
  log_groups = var.group_logs ? {
    # One log group for all runnables
    "__all__": "/aws/ecs/${var.environment_name}/${var.application_name}"
  } : {
    # One log group for each runnable
    for name, runnable in local.runnables:
    (name) => "/aws/ecs/${var.environment_name}/${var.application_name}/${runnable.name}"
  }
}

resource "aws_cloudwatch_log_group" "main" {
  for_each = local.log_groups
  name = each.value
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "logging" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      for name in keys(local.log_groups):
      "${aws_cloudwatch_log_group.main[name].arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "logging" {
  count = length(local.runnables) > 0 ? 1 : 0
  name = "logging"
  policy = data.aws_iam_policy_document.logging.json
  role = aws_iam_role.execute.id
}
