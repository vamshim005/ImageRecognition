module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "img-recognition-vpc"
  cidr   = "10.0.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
}

module "cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  name    = "img-recognition"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_sqs_queue" "jobs" {
  name                      = "image-jobs"
  visibility_timeout_seconds = 30
  kms_master_key_id         = "alias/aws/sqs"
}

# TODO: Add ALB, S3, IAM, ECS task/service modules 