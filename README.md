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
      command = ["cat", "/mnt/my-configuration"]
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
      tcp = {
        port = 22
        container_port = 2022
        load_balancer_name = "production-tcp"
      }
      placement_strategy = {
        type = "binpack"
        field = "memory"
      }
      mount_files = {
        "my-configuration" = "aGVsbG8gPSAid29ybGQiCg=="
      }
      efs_mounts = {
        "user-uploads": {
          file_system_id = module.user_uploads_file_system.id
          root_directory = "/"
          mount_path = "/app/uploads"
        }
      }
      auto_scaling = {
        min_instances = 1
        max_instances = 10
        cpu_threshold = 60
        memory_threshold = 80
      }
    }
    "worker" = {  # Fargate example
      memory = 1024
      cpu_units = 256
      launch_type = "FARGATE"
      is_spot = true
      desired_count = 2
      command = ["run-worker", "--some-option"]
      docker = {
        image_name = "acme-app"
        image_tag = "main"
        source = "ecr"
      }
      efs_mounts = {
        "user-uploads": {
          file_system_id = module.user_uploads_file_system.id
          root_directory = "/"
          mount_path = "/app/uploads"
        }
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
