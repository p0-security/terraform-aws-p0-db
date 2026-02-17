variable "aws_account_id" {
  description = "The AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
}

variable "create_connector" {
  description = "Whether to create the full connector infrastructure (true) or only add IAM auth policy to existing role (false)"
  type        = bool
  default     = false
}

variable "create_ecr" {
  description = "Whether to create a new ECR repository (true) or use an existing one (false)"
  type        = bool
  default     = false
}

variable "db_architecture" {
  description = "RDS database architecture: 'pg' for PostgreSQL or 'mysql' for MySQL/MariaDB"
  type        = string
  validation {
    condition     = contains(["pg", "mysql"], var.db_architecture)
    error_message = "db_architecture must be either 'pg' or 'mysql'"
  }
}

variable "db_identifier" {
  description = "The identifier of the RDS instance or cluster"
  type        = string
}

variable "db_type" {
  description = "Type of RDS resource: 'instance' or 'cluster'"
  type        = string
  default     = "instance"
  validation {
    condition     = contains(["instance", "cluster"], var.db_type)
    error_message = "db_type must be either 'instance' or 'cluster'"
  }
}

variable "vpc_id" {
  description = "The ID of the AWS VPC"
  type        = string
}
