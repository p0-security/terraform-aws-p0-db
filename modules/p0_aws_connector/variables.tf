variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the AWS VPC"
  type        = string
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for Lambda and VPC endpoints"
  type        = list(string)
}

variable "image_uri" {
  description = "Docker image URI for the Lambda function"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs for the Lambda function"
  type        = list(string)
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "invoker_role_name" {
  description = "Name of the IAM role that should be allowed to invoke the Lambda function"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for pushing Docker images"
  type        = string
}

variable "connector_image" {
  description = "Docker image name to pull and push to ECR"
  type        = string
}
