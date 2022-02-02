resource "aws_iam_role" "nodes" {
  /*
  Role to be assumed by the ECS instances
  */
  name = "i-${var.cluster_name}"
  path = "/"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume.json
}

data "aws_iam_policy_document" "nodes_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "nodes" {
  /*
  An IAM profile to associate to ECS instances
  */
  name = var.cluster_name
  role = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "nodes_ecs" {
  /*
  Attach the AWS-managed policy which contains permissions to use ECS features

  See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html
  */
  role = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
