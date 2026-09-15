variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
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
