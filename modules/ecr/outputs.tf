output "repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.p0_connector_images.repository_url
}

output "repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.p0_connector_images.arn
}

output "repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.p0_connector_images.name
}
