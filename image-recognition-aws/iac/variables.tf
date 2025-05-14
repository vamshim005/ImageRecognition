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

variable "project_id" {
  description = "Project identifier for resource naming"
  type        = string
  default     = "dev"
}

variable "acm_cert_arn" {
  description = "ACM certificate ARN for ALB HTTPS listener"
  type        = string
} 