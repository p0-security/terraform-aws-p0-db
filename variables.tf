variable "arch" {
  description = "Database architecture"
  type        = string
  validation {
    condition     = contains(["mysql", "pg"], var.arch)
    error_message = "'arch' must be one of 'mysql' or 'pg'"
  }
}

variable "aws_account_id" {
  description = "The AWS account ID"
  nullable    = true
  default     = null
  type        = string
}

variable "aws_region" {
  description = "The AWS region"
  nullable    = true
  default     = null
  type        = string
}

variable "lambda_execution_role_name" {
  description = "Name of the connector Lambda function's service role"
  type        = string
}

variable "rds_arn" {
  description = "RDS instance or cluster ARN"
  type        = string
}

variable "rds_resource_id" {
  description = "RDS instance or cluster resource ID"
  type        = string
}
