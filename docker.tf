locals {
  # Map of service names to their ECR repository, if set
  ecr_image_names = {
    for item_name, item in local.runnables:
    item_name => item.docker.image_name
    if item.docker.source == "ecr"
  }

  # Map of service name to their Docker image address
  docker_image_addresses = {
    for item_name, item in local.runnables:
    item_name => {
      "dockerhub" = "docker.io/${item.docker.image_name}"
      "public-ecr" = "public.ecr.aws/docker/library/${item.docker.image_name}"
      "ecr" = try(data.aws_ecr_repository.services[item_name].repository_url, null)
    }[item.docker.source]
  }
}

data "aws_ecr_repository" "services" {
  for_each = local.ecr_image_names
  name = each.value
}

data "aws_iam_policy_document" "pull_ecr_image" {
  statement {
    actions = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [
      for service_name in keys(local.ecr_image_names):
      data.aws_ecr_repository.services[service_name].arn
    ]
  }
}

resource "aws_iam_role_policy" "pull_ecr_image" {
  count = length(local.ecr_image_names) > 0 ? 1 : 0
  name = "pull-ecr-image"
  policy = data.aws_iam_policy_document.pull_ecr_image.json
  role = aws_iam_role.execute.id
}
