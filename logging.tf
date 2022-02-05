resource "aws_cloudwatch_log_group" "main" {
  for_each = var.services
  name = "/aws/ecs/${var.environment_name}/${var.application_name}/${each.key}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "logging" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      for service_name in keys(var.services):
      "${aws_cloudwatch_log_group.main[service_name].arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "logging" {
  name = "logging"
  policy = data.aws_iam_policy_document.logging.json
  role = aws_iam_role.ecs_agent.id
}
