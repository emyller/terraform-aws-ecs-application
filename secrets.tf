locals {
  # Collect a map of services and scheduled tasks and their secrets
  service_secrets = {
    for item_name, item in local.runnables:
    item_name => {
      for env_var_name, secret_name in coalesce(item.secrets, var.secrets):
      ("${item_name}/${env_var_name}") => {
        service_name = item_name
        env_var_name = env_var_name
        secret_name = secret_name
      }
    }
  }
  flattened_service_secrets = merge(values(local.service_secrets)...)
}

data "aws_secretsmanager_secret" "services" {
  for_each = local.flattened_service_secrets
  name = each.value.secret_name
}

data "aws_iam_policy_document" "get_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      for service_secret in keys(local.flattened_service_secrets):
      data.aws_secretsmanager_secret.services[service_secret].arn
    ]
  }
}

resource "aws_iam_role_policy" "get_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  name = "get-secrets"
  policy = data.aws_iam_policy_document.get_secrets.json
  role = aws_iam_role.execute.id
}
