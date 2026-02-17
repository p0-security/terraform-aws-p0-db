variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "p0_connector_images"
}

variable "image_limit" {
  description = "Maximum number of images to keep in the repository"
  type        = number
  default     = 10
}
