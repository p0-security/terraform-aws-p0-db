output "database" {
  description = "RDS database information"
  value = {
    subnet_group = local.db_subnet_group
    resource_id  = local.db_resource_id
    endpoint     = var.db_type == "instance" ? data.aws_db_instance.target[0].endpoint : data.aws_rds_cluster.target[0].endpoint
    port         = local.db_port
  }
}

output "security_group_id" {
  description = "ID of the security group for P0 database endpoint"
  value       = var.create_connector ? aws_security_group.p0_db_endpoint[0].id : null
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for P0 connector images"
  value       = local.ecr_repository_url
}

output "connector_lambda" {
  description = "P0 connector Lambda function details"
  value = var.create_connector ? {
    arn                = aws_lambda_function.p0_connector[0].arn
    name               = aws_lambda_function.p0_connector[0].function_name
    execution_role_arn = local.lambda_execution_role.arn
  } : null
}

output "lambda_execution_role" {
  description = "Lambda execution role details"
  value = {
    arn  = local.lambda_execution_role.arn
    name = local.lambda_execution_role.name
  }
}
