module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.0"

  repository_name                 = "${var.project}/final-project-${var.owner}"
  repository_image_tag_mutability = "MUTABLE"
  repository_force_delete         = true

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
