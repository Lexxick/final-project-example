variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "availability_zone" {
  description = "Single availability zone used by both subnets (must be in var.region)"
  type        = string
  default     = "ap-southeast-1a"
}

variable "project" {
  description = "Project name, used for resource names and the Project tag"
  type        = string
  default     = "devops-bootcamp"
}

variable "owner" {
  description = "Owner identifier, used as a suffix on globally unique names and as the Owner tag"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository (owner/name) cloned by the controller"
  type        = string
}

variable "github_oidc_subject" {
  description = "Repository part of the GitHub OIDC subject claim (owner@id/name@id for repositories created after July 2026)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for all three servers"
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/24"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/25"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.0.128/25"
}

variable "web_private_ip" {
  description = "Private IP of the web server (public subnet)"
  type        = string
  default     = "10.0.0.5"
}

variable "controller_private_ip" {
  description = "Private IP of the Ansible controller (private subnet)"
  type        = string
  default     = "10.0.0.135"
}

variable "monitoring_private_ip" {
  description = "Private IP of the monitoring server (private subnet)"
  type        = string
  default     = "10.0.0.136"
}
