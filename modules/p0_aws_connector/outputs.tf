output "lambda_function" {
  description = "Lambda function details"
  value = {
    arn  = aws_lambda_function.connector.arn
    name = aws_lambda_function.connector.function_name
  }
}

output "lambda_execution_role" {
  description = "Lambda execution role details"
  value = {
    arn  = aws_iam_role.lambda_execution.arn
    name = aws_iam_role.lambda_execution.name
  }
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
