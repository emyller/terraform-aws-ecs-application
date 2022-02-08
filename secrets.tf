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
