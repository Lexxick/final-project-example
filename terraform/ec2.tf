locals {
  ubuntu_ami_parameter = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

module "web_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name               = "devops-web-server"
  ami_ssm_parameter  = local.ubuntu_ami_parameter
  ignore_ami_changes = true
  instance_type      = var.instance_type

  subnet_id              = module.vpc.public_subnets[0]
  private_ip             = var.web_private_ip
  create_eip             = true
  create_security_group  = false
  vpc_security_group_ids = [module.public_sg.id]
  iam_instance_profile   = module.web_role.instance_profile_name

  tags = {
    Role = "web"
  }
}

module "controller" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name               = "devops-ansible-controller"
  ami_ssm_parameter  = local.ubuntu_ami_parameter
  ignore_ami_changes = true
  instance_type      = var.instance_type

  subnet_id              = module.vpc.private_subnets[0]
  private_ip             = var.controller_private_ip
  create_security_group  = false
  vpc_security_group_ids = [module.private_sg.id]
  iam_instance_profile   = module.controller_role.instance_profile_name

  user_data = templatefile("${path.module}/templates/controller.sh.tftpl", {
    repository_url = "https://github.com/${var.github_repository}.git"
  })
  user_data_replace_on_change = true

  tags = {
    Role = "controller"
  }
}

module "monitoring_server" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name               = "devops-monitoring-server"
  ami_ssm_parameter  = local.ubuntu_ami_parameter
  ignore_ami_changes = true
  instance_type      = var.instance_type

  subnet_id              = module.vpc.private_subnets[0]
  private_ip             = var.monitoring_private_ip
  create_security_group  = false
  vpc_security_group_ids = [module.private_sg.id]
  iam_instance_profile   = module.monitoring_role.instance_profile_name

  tags = {
    Role = "monitoring"
  }
}
