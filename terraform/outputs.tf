###############################################################
# outputs.tf
###############################################################

output "ec2_public_ip" {
  description = "Elastic IP of the EC2 instance"
  value       = aws_eip.app_eip.public_ip
}

output "app_url" {
  description = "Node.js application URL"
  value       = "http://${aws_eip.app_eip.public_ip}:9000"
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${aws_eip.app_eip.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${aws_eip.app_eip.public_ip}:9090"
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing your Docker image"
  value       = aws_ecr_repository.nodejs_app.repository_url
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/id_rsa ec2-user@${aws_eip.app_eip.public_ip}"
}
