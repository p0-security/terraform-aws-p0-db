terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data source to get RDS instance details
data "aws_db_instance" "target" {
  count                  = var.db_type == "instance" ? 1 : 0
  db_instance_identifier = var.db_identifier
}

# Data source to get RDS cluster details
data "aws_rds_cluster" "target" {
  count              = var.db_type == "cluster" ? 1 : 0
  cluster_identifier = var.db_identifier
}

# Data source to get VPC details
data "aws_vpc" "target" {
  id = var.vpc_id
}

# Data source to get subnets in the VPC
data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Local values for computed attributes
locals {
  db_subnet_group = var.db_type == "instance" ? data.aws_db_instance.target[0].db_subnet_group : data.aws_rds_cluster.target[0].db_subnet_group_name
  db_resource_id  = var.db_type == "instance" ? data.aws_db_instance.target[0].resource_id : data.aws_rds_cluster.target[0].cluster_resource_id
  db_security_groups = var.db_type == "instance" ? data.aws_db_instance.target[0].vpc_security_groups : data.aws_rds_cluster.target[0].vpc_security_group_ids
  db_port = var.db_type == "instance" ? data.aws_db_instance.target[0].port : data.aws_rds_cluster.target[0].port
  connector_image = "p0security/p0-connector-${var.db_architecture}:latest"
  ecr_repository_url = var.create_ecr ? module.ecr[0].repository_url : data.aws_ecr_repository.p0_connector_images[0].repository_url
  lambda_execution_role = var.create_connector ? module.p0_aws_connector[0].lambda_execution_role : data.aws_iam_role.lambda_execution[0]
}

# Security group for database access (only when create_connector is true)
resource "aws_security_group" "db_access" {
  count       = var.create_connector ? 1 : 0
  name        = "p0_db_access_${var.vpc_id}"
  description = "Security group for P0 connector to access RDS database"
  vpc_id      = var.vpc_id

  # Allow outbound traffic to RDS instance/cluster
  egress {
    description     = "Allow outbound to RDS database"
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = local.db_security_groups
  }

  tags = {
    Name       = "p0_db_access_${var.vpc_id}"
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# P0 AWS Connector module (only when create_connector is true)
module "p0_aws_connector" {
  count  = var.create_connector ? 1 : 0
  source = "./modules/p0_aws_connector"

  function_name      = "p0-connector-${var.db_architecture}-${var.vpc_id}"
  vpc_id             = var.vpc_id
  aws_region         = var.aws_region
  subnet_ids         = data.aws_subnets.vpc_subnets.ids
  route_table_ids    = data.aws_route_tables.vpc_route_tables.ids
  image_uri          = "${local.ecr_repository_url}:latest"
  security_group_ids = [aws_security_group.db_access[0].id]
  invoker_role_name  = data.aws_iam_role.p0_rds_connector.name

  environment_variables = {
    DB_TYPE       = var.db_architecture
    DB_IDENTIFIER = var.db_identifier
    DB_PORT       = tostring(local.db_port)
    VPC_ID        = var.vpc_id
  }

  timeout     = 300
  memory_size = 512

  depends_on = [
    null_resource.push_image
  ]
}

# Data source to get route tables for the VPC
data "aws_route_tables" "vpc_route_tables" {
  vpc_id = var.vpc_id
}

# Data source to read existing ECR repository (when create_ecr is false)
data "aws_ecr_repository" "p0_connector_images" {
  count = var.create_ecr ? 0 : 1
  name  = "p0_connector_images"
}

# ECR module for creating repository (when create_ecr is true)
module "ecr" {
  count  = var.create_ecr ? 1 : 0
  source = "./modules/ecr"

  repository_name = "p0_connector_images"
  image_limit     = 10
}

# Data source to get ECR authorization token
data "aws_ecr_authorization_token" "token" {
  count = var.create_connector ? 1 : 0
}

# Null resource to pull, tag, and push Docker image to ECR (only when create_connector is true)
resource "null_resource" "push_image" {
  count = var.create_connector ? 1 : 0

  triggers = {
    ecr_repository_url = local.ecr_repository_url
    image_name         = local.connector_image
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Pull the source image for linux/amd64 platform
      docker pull --platform linux/amd64 ${local.connector_image}

      # Tag for ECR
      docker tag ${local.connector_image} ${local.ecr_repository_url}:latest

      # Login to ECR
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_repository_url}

      # Push to ECR
      docker push ${local.ecr_repository_url}:latest
    EOT
  }

  depends_on = [
    module.ecr,
    data.aws_ecr_repository.p0_connector_images
  ]
}

# Data source to read existing Lambda execution role (when create_connector is false)
data "aws_iam_role" "lambda_execution" {
  count = var.create_connector ? 0 : 1
  name  = "P0ConnectorLambdaExecution-${var.vpc_id}"
}

# IAM policy to allow Lambda to authenticate to RDS using IAM
resource "aws_iam_policy" "lambda_rds_iam_auth" {
  name        = "P0ConnectorRdsIamAuth-${var.vpc_id}"
  description = "Policy allowing Lambda to use IAM authentication to connect to RDS as p0_iam_manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${local.db_resource_id}/p0_iam_manager"
      }
    ]
  })

  tags = {
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# Attach RDS IAM auth policy to Lambda role (always created)
resource "aws_iam_role_policy_attachment" "lambda_rds_iam_auth" {
  role       = local.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_rds_iam_auth.arn
}


# Data source to get the P0 RDS Connector IAM role
data "aws_iam_role" "p0_rds_connector" {
  name = "P0RdsConnector-${var.vpc_id}"
}
