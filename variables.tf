variable "lambda_execution_role_name" {
  description = "Name of the connector Lambda function's service role"
  type        = string
}

variable "rds_cluster_arn" {
  description = "ARN of the RDS cluster. Set exactly one of rds_cluster_arn or rds_instance_arn."
  type        = string
  default     = null

  validation {
    condition     = (var.rds_cluster_arn == null) != (var.rds_instance_arn == null)
    error_message = "Exactly one of rds_cluster_arn or rds_instance_arn must be set."
  }
}

variable "rds_instance_arn" {
  description = "ARN of the RDS DB instance. Set exactly one of rds_cluster_arn or rds_instance_arn."
  type        = string
  default     = null
}

variable "connector_security_group_id" {
  description = "ID of the P0 connector Lambda's security group."
  type        = string
}
