terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
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
  subnet_ids          = var.subnet_ids
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
  subnet_ids          = var.subnet_ids
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
  route_table_ids   = var.route_table_ids

  tags = {
    Name       = "${var.function_name}-s3"
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
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
    subnet_ids         = var.subnet_ids
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
    aws_iam_role_policy_attachment.lambda_ecr_read
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
