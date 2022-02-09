# ecs-application

Create and plug an application into an existing ECS cluster.


## Example

```hcl
module "application" {
  source = "..."

  application_name = "acme-app"
  environment_name = "production"
  cluster_name = "production-web"  # See the ecs-cluster module
  subnets = data.aws_subnet_ids.private.ids
  services = {
    "app" = {
      memory = 512
      desired_count = 1
      docker = {
        image_name = "acme-app"
        image_tag = "main"
        source = "ecr"
      }
      http = {
        port = 3005
        load_balancer_name = "production-web"
        hostnames = ["app.example.com"]
        health_check = { path = "/", status_codes = [200, 302] }
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
