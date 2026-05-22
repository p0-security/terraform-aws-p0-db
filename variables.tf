variable "lambda_execution_role_name" {
  description = "Name of the connector Lambda function's service role"
  type        = string
}

variable "rds_arn" {
  description = "RDS instance or cluster ARN"
  type        = string
}

variable "connector_security_group_id" {
  description = "ID of the P0 connector Lambda's security group."
  type        = string
}

variable "aws_region" {
  description = "The AWS region"
  nullable    = true
  default     = null
  type        = string
}
