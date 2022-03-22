# ecs-application

A Terraform module to manage an application in AWS ECS.


## Usage example

```hcl
module "application" {
  source = "emyller/ecs-application/aws"
  version = "~> 2.0"

  application_name = "acme-app"
  environment_name = "production"
  cluster_name = "production-web"  # See the ecs-cluster module
  subnets = data.aws_subnet_ids.private.ids
  services = {
    "app" = {
      memory = 512
      desired_count = 1
      command = ["uwsgi", "--ini", "app.ini"]
      docker = {
        image_name = "acme-app"
        image_tag = "main"
        source = "ecr"
      }
      http = {
        port = 3005
        load_balancer_name = "production-web"
        listener_rule = { hostnames = ["app.example.com"] }
        health_check = { path = "/", status_codes = [200, 302] }
      }
      placement_strategy = { type = "binpack", field = "memory" }
    }
  }
  scheduled_tasks = {
    "say-hello" = {
      memory = 128
      command = ["echo", "hello"]
      docker = {
        image_name = "acme-app"
        image_tag = "main"
        source = "ecr"
      }
    }
  }

  environment_variables = {
    "PORT" = 3005
  }

  secrets = {
    "SECRET_KEY" = "production/acme-app/SECRET_KEY"
  }
}
```
