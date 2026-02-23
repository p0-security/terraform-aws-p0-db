variable "lambda_execution_role_name" {
  description = "Name of the connector Lambda function's service role"
  type        = string
}

variable "rds_arn" {
  description = "RDS instance or cluster ARN"
  type        = string
}

variable "connector_security_group_id" {
  description = "ID of the security group that must be able to ingress to the database, used to allow the connector to access the database. This security group must exist and be attached to the database before applying this module."
  type        = string
}
