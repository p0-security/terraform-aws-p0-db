terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ECR Repository for P0 connector images
resource "aws_ecr_repository" "p0_connector_images" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    ManagedBy  = "Terraform"
    ManagedFor = "P0"
  }
}

# ECR Lifecycle Policy to keep only recent images
resource "aws_ecr_lifecycle_policy" "p0_connector_images" {
  repository = aws_ecr_repository.p0_connector_images.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.image_limit} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.image_limit
      }
      action = {
        type = "expire"
      }
    }]
  })
}
