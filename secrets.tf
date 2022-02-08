data "aws_secretsmanager_secret" "services" {
  for_each = var.secrets
  name = each.value
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

resource "aws_iam_role_policy" "get_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  name = "get-secrets"
  policy = data.aws_iam_policy_document.get_secrets.json
  role = aws_iam_role.ecs_agent.id
}
