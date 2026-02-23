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

data "aws_rds_cluster" "database" {
  cluster_identifier = reverse(split(":", var.rds_arn))[0]
}

data "aws_security_group" "database" {
  id = tolist(data.aws_rds_cluster.database.vpc_security_group_ids)[0]
}

locals {
  aws_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  aws_region     = coalesce(var.aws_region, data.aws_region.current.id)
}

# Security group rules allowing connector to access database
resource "aws_security_group_rule" "connector_to_database" {
  type                     = "egress"
  description              = "Outbound to database"
  from_port                = data.aws_rds_cluster.database.port
  to_port                  = data.aws_rds_cluster.database.port
  protocol                 = "tcp"
  security_group_id        = var.connector_security_group_id
  source_security_group_id = data.aws_security_group.database.id
}

resource "aws_security_group_rule" "database_from_connector" {
  type                     = "ingress"
  description              = "Database traffic from P0 connector Lambda"
  from_port                = data.aws_rds_cluster.database.port
  to_port                  = data.aws_rds_cluster.database.port
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.database.id
  source_security_group_id = var.connector_security_group_id
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
