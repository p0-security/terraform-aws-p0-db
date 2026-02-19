terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  aws_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  aws_region     = coalesce(var.aws_region, data.aws_region.current.id)
}

# RDS describe and connect policy for Lambda
resource "aws_iam_role_policy" "lambda_rds_describe" {
  name = "P0RdsSecurityPerimeterDescribePolicy"
  role = var.lambda_execution_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConnectToRdsCluster"
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${local.aws_region}:${local.aws_account_id}:dbuser:${var.rds_resource_id}/p0_iam_manager"
        ]
      }
    ]
  })
}
