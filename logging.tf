resource "aws_cloudwatch_log_group" "main" {
  for_each = local.runnables
  name = "/aws/ecs/${var.environment_name}/${var.application_name}/${each.value.name}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "logging" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      for item_name in keys(local.runnables):
      "${aws_cloudwatch_log_group.main[item_name].arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "logging" {
  count = length(local.runnables) > 0 ? 1 : 0
  name = "logging"
  policy = data.aws_iam_policy_document.logging.json
  role = aws_iam_role.execute.id
}
