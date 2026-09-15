# The registry is owned by terraform/bootstrap so images survive terraform destroy.
data "aws_ecr_repository" "app" {
  name = "${var.project}/final-project-${var.owner}"
}
