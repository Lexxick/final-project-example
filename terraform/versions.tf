terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "devops-bootcamp-terraform-syedazam-507861383583"
    key          = "final-project/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}
