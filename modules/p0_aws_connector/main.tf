terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Data source to get ECR authorization token
data "aws_ecr_authorization_token" "token" {}

# Data source to get subnets in the VPC
data "aws_subnets" "vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Data source to get route tables for the VPC
data "aws_route_tables" "vpc_route_tables" {
  vpc_id = var.vpc_id
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.function_name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  # Allow outbound HTTPS for ECR and other AWS services
  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS from VPC (for VPC endpoint communication)
  ingress {
    description = "Allow inbound HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "${var.function_name}-vpc-endpoints"
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# VPC Endpoint for ECR API (needed for Lambda to pull images)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name       = "${var.function_name}-ecr-api"
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# VPC Endpoint for ECR Docker (needed for Lambda to pull images)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.vpc_subnets.ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name       = "${var.function_name}-ecr-dkr"
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# VPC Endpoint for S3 (Gateway endpoint, needed for Lambda to pull layers from ECR)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc_route_tables.ids

  tags = {
    Name       = "${var.function_name}-s3"
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# Null resource to pull, tag, and push Docker image to ECR
resource "null_resource" "push_image" {
  triggers = {
    ecr_repository_url = var.ecr_repository_url
    image_name         = var.connector_image
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Pull the source image for linux/amd64 platform
      docker pull --platform linux/amd64 ${var.connector_image}

      # Tag for ECR
      docker tag ${var.connector_image} ${var.ecr_repository_url}:latest

      # Login to ECR
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${var.ecr_repository_url}

      # Push to ECR
      docker push ${var.ecr_repository_url}:latest
    EOT
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution" {
  name = "${var.function_name}-execution"

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
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# Attach VPC execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach ECR read policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_ecr_read" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Lambda function using container image from ECR
resource "aws_lambda_function" "connector" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_execution.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  timeout       = var.timeout
  memory_size   = var.memory_size

  vpc_config {
    subnet_ids         = data.aws_subnets.vpc_subnets.ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = var.environment_variables
  }

  tags = {
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc_execution,
    aws_iam_role_policy_attachment.lambda_ecr_read,
    null_resource.push_image
  ]
}

# IAM policy to allow specified role to invoke Lambda function
resource "aws_iam_policy" "invoke_lambda" {
  name        = "${var.function_name}-invoke"
  description = "Policy allowing ${var.invoker_role_name} to invoke the ${var.function_name} Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.connector.arn
      }
    ]
  })

  tags = {
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# Attach the invoke policy to the specified role
resource "aws_iam_role_policy_attachment" "invoke_lambda" {
  role       = var.invoker_role_name
  policy_arn = aws_iam_policy.invoke_lambda.arn
}
