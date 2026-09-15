module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "devops-vpc"
  cidr = var.vpc_cidr
  azs  = [var.availability_zone]

  public_subnets       = [var.public_subnet_cidr]
  public_subnet_names  = ["devops-public-subnet"]
  private_subnets      = [var.private_subnet_cidr]
  private_subnet_names = ["devops-private-subnet"]

  enable_nat_gateway = true
  single_nat_gateway = true

  igw_tags                 = { Name = "devops-igw" }
  nat_gateway_tags         = { Name = "devops-ngw" }
  public_route_table_tags  = { Name = "devops-public-route" }
  private_route_table_tags = { Name = "devops-private-route" }
}
