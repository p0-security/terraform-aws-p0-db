terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  is_cluster     = split(":", var.rds_arn)[5] == "cluster"
  aws_account_id = split(":", var.rds_arn)[4]
  aws_region     = split(":", var.rds_arn)[3]
  aws_partition  = split(":", var.rds_arn)[1]
}

data "aws_rds_cluster" "database" {
  count              = local.is_cluster ? 1 : 0
  cluster_identifier = reverse(split(":", var.rds_arn))[0]
}

data "aws_db_instance" "database" {
  count                  = local.is_cluster ? 0 : 1
  db_instance_identifier = reverse(split(":", var.rds_arn))[0]
}

locals {
  database_security_group_id = local.is_cluster ? tolist(data.aws_rds_cluster.database[0].vpc_security_group_ids)[0] : tolist(data.aws_db_instance.database[0].vpc_security_groups)[0]
  port                       = local.is_cluster ? data.aws_rds_cluster.database[0].port : data.aws_db_instance.database[0].port
  resource_id                = local.is_cluster ? data.aws_rds_cluster.database[0].cluster_resource_id : data.aws_db_instance.database[0].resource_id
}

# Security group rules allowing connector to access database
resource "aws_security_group_rule" "connector_to_database" {
  type                     = "egress"
  description              = "Outbound to database"
  from_port                = local.port
  to_port                  = local.port
  protocol                 = "tcp"
  security_group_id        = var.connector_security_group_id
  source_security_group_id = local.database_security_group_id
}

resource "aws_security_group_rule" "database_from_connector" {
  type                     = "ingress"
  description              = "Database traffic from P0 connector Lambda"
  from_port                = local.port
  to_port                  = local.port
  protocol                 = "tcp"
  security_group_id        = local.database_security_group_id
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
          "arn:${local.aws_partition}:rds-db:${local.aws_region}:${local.aws_account_id}:dbuser:${local.resource_id}/p0_iam_manager"
        ]
      }
    ]
  })
}
