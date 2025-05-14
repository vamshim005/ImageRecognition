variable "web_image" {
  description = "Docker image for the web service"
  type        = string
}

variable "worker_image" {
  description = "Docker image for the worker service"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
} 