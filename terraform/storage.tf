# Scratch bucket for the aws_ssm connection plugin (file transfer to managed hosts).
module "ansible_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket        = "${var.project}-ansible-${var.owner}"
  force_destroy = true

  lifecycle_rule = [
    {
      id      = "expire-transfers"
      enabled = true
      expiration = {
        days = 1
      }
    }
  ]
}
