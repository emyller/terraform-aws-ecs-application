locals {
  # Collect a map of services and their secrets
  service_secrets = {
    for service_name, service in merge(var.services, var.scheduled_tasks):
    (service_name) => {
      for env_var_name, secret_name in coalesce(service.secrets, var.secrets):
      ("${service_name}/${env_var_name}") => {
        service_name = service_name
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
  role = aws_iam_role.ecs_agent.id
}
