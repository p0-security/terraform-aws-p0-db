variable "connector_lambda_name" {
  description = "Name of the connector Lambda function's service role"
  type        = string
}

variable "rds_arn" {
  description = "RDS instance or cluster ARN"
  type        = string
}
