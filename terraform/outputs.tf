output "web_public_ip" {
  description = "Elastic IP of the web server"
  value       = module.web_server.public_ip
}

output "web_instance_id" {
  description = "Instance ID of the web server"
  value       = module.web_server.id
}

output "controller_instance_id" {
  description = "Instance ID of the Ansible controller"
  value       = module.controller.id
}

output "monitoring_instance_id" {
  description = "Instance ID of the monitoring server"
  value       = module.monitoring_server.id
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application image"
  value       = module.ecr.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN to set as the AWS_ROLE_ARN repository variable"
  value       = module.github_actions_role.arn
}

output "controller_session_command" {
  description = "Open a Session Manager shell on the Ansible controller"
  value       = "aws ssm start-session --target ${module.controller.id} --region ${var.region}"
}
