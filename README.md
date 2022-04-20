# ecs-application

A Terraform module to manage an application in AWS ECS.


## Usage example

```hcl
module "application" {
  source = "emyller/ecs-application/aws"
  version = "~> 3.0"

  application_name = "acme-app"
  environment_name = "production"
  cluster_name = "production-web"  # See the ecs-cluster module
  subnets = data.aws_subnet_ids.private.ids

  services = {
    "app" = {  # EC2 example
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
    "worker" = {  # Fargate example
      memory = 1024
      cpu_units = 256
      launch_type = "FARGATE"
      desired_count = 2
      command = ["run-worker", "--some-option"]
      docker = {
        image_name = "acme-app"
        image_tag = "main"
        source = "ecr"
      }
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

  reactive_tasks = {
    "process-upload" = {
      launch_type = "FARGATE"
      memory = 512
      command = item.command
      docker = {
        image_name = module.ecr.repository.name
        image_tag = "master"
        source = "ecr"
      }
      event_pattern = {
        source = ["aws.s3"]
        detail_type = ["Object Created"]
        detail = {
          "bucket": { "name": "prod-uploads" }
          "object": { "key": [{ "prefix": "user/avatars/" }] }
        }
      }
      event_variables = {
        bucket = "$.detail.bucket.name"
        key = "$.detail.object.key"
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
