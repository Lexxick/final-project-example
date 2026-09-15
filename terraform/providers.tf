provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "devops-bootcamp-terraform-${var.owner}-${local.account_id}"
  state_key    = "final-project/terraform.tfstate"
}
