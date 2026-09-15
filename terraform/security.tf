module "public_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name            = "devops-public-sg"
  use_name_prefix = false
  description     = "Web server: HTTP from anywhere, node_exporter from the monitoring server"
  vpc_id          = module.vpc.vpc_id

  ingress_rules = {
    http = {
      description = "HTTP"
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    node_exporter = {
      description = "node_exporter scrape from Prometheus"
      from_port   = 9100
      to_port     = 9100
      ip_protocol = "tcp"
      cidr_ipv4   = "${var.monitoring_private_ip}/32"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

module "private_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name            = "devops-private-sg"
  use_name_prefix = false
  description     = "Private servers: no inbound, outbound via NAT"
  vpc_id          = module.vpc.vpc_id

  ingress_rules = {}

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}
