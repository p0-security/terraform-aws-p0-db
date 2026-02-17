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
  lambda_execution_role = var.create_connector ? aws_iam_role.lambda_execution[0] : data.aws_iam_role.lambda_execution[0]
}

# Security group for VPC endpoint and Lambda (only when create_connector is true)
resource "aws_security_group" "p0_db_endpoint" {
  count       = var.create_connector ? 1 : 0
  name        = "p0_db_endpoint_${var.vpc_id}"
  description = "Security group for P0 database connector endpoint"
  vpc_id      = var.vpc_id

  # Allow outbound traffic to RDS instance/cluster
  egress {
    description     = "Allow outbound to RDS database"
    from_port       = local.db_port
    to_port         = local.db_port
    protocol        = "tcp"
    security_groups = local.db_security_groups
  }

  # Allow all outbound HTTPS for ECR and other AWS services
  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound from VPC CIDR (for VPC endpoint communication)
  ingress {
    description = "Allow inbound from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.target.cidr_block]
  }

  tags = {
    Name       = "p0_db_endpoint_${var.vpc_id}"
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# VPC Endpoint for ECR API (needed for Lambda to pull images) (only when create_connector is true)
resource "aws_vpc_endpoint" "ecr_api" {
  count               = var.create_connector ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  security_group_ids  = [aws_security_group.p0_db_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name       = "p0_ecr_api_${var.vpc_id}"
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# VPC Endpoint for ECR Docker (needed for Lambda to pull images) (only when create_connector is true)
resource "aws_vpc_endpoint" "ecr_dkr" {
  count               = var.create_connector ? 1 : 0
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  security_group_ids  = [aws_security_group.p0_db_endpoint[0].id]
  private_dns_enabled = true

  tags = {
    Name       = "p0_ecr_dkr_${var.vpc_id}"
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# VPC Endpoint for S3 (Gateway endpoint, needed for Lambda to pull layers from ECR) (only when create_connector is true)
resource "aws_vpc_endpoint" "s3" {
  count             = var.create_connector ? 1 : 0
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc_route_tables.ids

  tags = {
    Name       = "p0_s3_${var.vpc_id}"
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
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

# IAM role for Lambda execution (only when create_connector is true)
resource "aws_iam_role" "lambda_execution" {
  count = var.create_connector ? 1 : 0
  name  = "P0ConnectorLambdaExecution-${var.vpc_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# Attach VPC execution policy to Lambda role (only when create_connector is true)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count      = var.create_connector ? 1 : 0
  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach ECR read policy to Lambda role (only when create_connector is true)
resource "aws_iam_role_policy_attachment" "lambda_ecr_read" {
  count      = var.create_connector ? 1 : 0
  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
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

# Lambda function using container image from ECR (only when create_connector is true)
resource "aws_lambda_function" "p0_connector" {
  count         = var.create_connector ? 1 : 0
  function_name = "p0-connector-${var.db_architecture}-${var.vpc_id}"
  role          = aws_iam_role.lambda_execution[0].arn
  package_type  = "Image"
  image_uri     = "${local.ecr_repository_url}:latest"
  timeout       = 300
  memory_size   = 512

  vpc_config {
    subnet_ids         = data.aws_subnets.vpc_subnets.ids
    security_group_ids = [aws_security_group.p0_db_endpoint[0].id]
  }

  environment {
    variables = {
      DB_TYPE       = var.db_architecture
      DB_IDENTIFIER = var.db_identifier
      DB_PORT       = local.db_port
      VPC_ID        = var.vpc_id
    }
  }

  tags = {
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }

  depends_on = [
    null_resource.push_image,
    aws_iam_role_policy_attachment.lambda_vpc_execution,
    aws_iam_role_policy_attachment.lambda_ecr_read
  ]
}

# Data source to get the P0 RDS Connector IAM role
data "aws_iam_role" "p0_rds_connector" {
  name = "P0RdsConnector-${var.vpc_id}"
}

# IAM policy to allow P0 RDS Connector role to invoke Lambda
resource "aws_iam_policy" "p0_invoke_lambda" {
  name        = "P0InvokeLambda-${var.vpc_id}"
  description = "Policy allowing P0 RDS Connector to invoke the connector Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.p0_connector.arn
      }
    ]
  })

  tags = {
    VpcId      = var.vpc_id
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# Attach the invoke policy to the P0 RDS Connector role
resource "aws_iam_role_policy_attachment" "p0_invoke_lambda" {
  role       = data.aws_iam_role.p0_rds_connector.name
  policy_arn = aws_iam_policy.p0_invoke_lambda.arn
}
