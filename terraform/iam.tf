locals {
  ssm_core_policy = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

  ec2_trust = {
    EC2AssumeRole = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }]
    }
  }
}

# Web server: SSM agent + pull the application image from ECR.
module "web_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name                     = "devops-web-role"
  use_name_prefix          = false
  trust_policy_permissions = local.ec2_trust
  create_instance_profile  = true

  policies = {
    ssm_core = local.ssm_core_policy
  }

  create_inline_policy = true
  inline_policy_permissions = {
    EcrLogin = {
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    EcrPull = {
      actions = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
      ]
      resources = [data.aws_ecr_repository.app.arn]
    }
  }
}

# Ansible controller: SSM sessions into tagged instances, inventory discovery,
# secrets from Parameter Store and the aws_ssm file-transfer bucket.
module "controller_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name                     = "devops-controller-role"
  use_name_prefix          = false
  trust_policy_permissions = local.ec2_trust
  create_instance_profile  = true

  policies = {
    ssm_core = local.ssm_core_policy
  }

  create_inline_policy = true
  inline_policy_permissions = {
    SessionTargets = {
      actions   = ["ssm:StartSession"]
      resources = ["arn:aws:ec2:${var.region}:${local.account_id}:instance/*"]
      condition = [{
        test     = "StringEquals"
        variable = "ssm:resourceTag/Project"
        values   = [var.project]
      }]
    }
    SessionDocument = {
      actions   = ["ssm:StartSession"]
      resources = ["arn:aws:ssm:${var.region}:${local.account_id}:document/SSM-SessionManagerRunShell"]
    }
    SessionLifecycle = {
      actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
      resources = ["*"]
    }
    Inventory = {
      actions   = ["ec2:DescribeInstances"]
      resources = ["*"]
    }
    Parameters = {
      actions   = ["ssm:GetParameter", "ssm:GetParameters"]
      resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter/${var.project}/*"]
    }
    TransferBucket = {
      actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
      resources = [module.ansible_bucket.s3_bucket_arn]
    }
    TransferObjects = {
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = ["${module.ansible_bucket.s3_bucket_arn}/*"]
    }
  }
}

# Monitoring server: SSM agent only.
module "monitoring_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name                     = "devops-monitoring-role"
  use_name_prefix          = false
  trust_policy_permissions = local.ec2_trust
  create_instance_profile  = true

  policies = {
    ssm_core = local.ssm_core_policy
  }
}

# GitHub Actions: plan on PRs, push images, trigger the deploy playbook on the controller.
module "github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "~> 6.0"
}

module "github_actions_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.0"

  name            = "devops-github-actions-role"
  use_name_prefix = false

  enable_github_oidc     = true
  oidc_wildcard_subjects = ["${var.github_oidc_subject}:*"]

  policies = {
    read_only = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  create_inline_policy = true
  inline_policy_permissions = {
    EcrLogin = {
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
    EcrPush = {
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = [data.aws_ecr_repository.app.arn]
    }
    DeployCommand = {
      actions   = ["ssm:SendCommand"]
      resources = ["arn:aws:ec2:${var.region}:${local.account_id}:instance/*"]
      condition = [{
        test     = "StringEquals"
        variable = "ssm:resourceTag/Role"
        values   = ["controller"]
      }]
    }
    DeployDocument = {
      actions   = ["ssm:SendCommand"]
      resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
    }
    DeployStatus = {
      actions   = ["ssm:GetCommandInvocation"]
      resources = ["*"]
    }
    StateLock = {
      actions   = ["s3:PutObject", "s3:DeleteObject"]
      resources = ["arn:aws:s3:::${local.state_bucket}/${local.state_key}.tflock"]
    }
  }

  depends_on = [module.github_oidc_provider]
}
