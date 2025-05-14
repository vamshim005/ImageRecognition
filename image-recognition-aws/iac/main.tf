module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
  name   = "img-recognition-vpc"
  cidr   = "10.0.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
}

module "cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.8.0"
  name    = "img-recognition"
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_sqs_queue" "jobs" {
  name                      = "image-jobs"
  visibility_timeout_seconds = 30
  kms_master_key_id         = "alias/aws/sqs"
}

resource "aws_s3_bucket" "raw" {
  bucket = "imgrec-raw-${var.project_id}"
  lifecycle_rule {
    prefix = ""
    enabled = true
    versioning {
      enabled = true
    }
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "alias/aws/s3"
        sse_algorithm     = "aws:kms"
      }
    }
  }
  block_public_acls   = true
  block_public_policy = true
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.7.0"
  name    = "imgrec"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  enable_http2       = true
  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.acm_cert_arn
      target_groups = [
        {
          name_prefix      = "web-"
          backend_port     = 8080
          backend_protocol = "HTTP"
          target_type      = "ip"
        }
      ]
    }
  }
}

module "web_task_role" {
  source = "./modules/iam-ecs-task-role"
  name   = "web-task-role"
  policies = {
    s3_put = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = ["s3:PutObject"],
        Effect = "Allow",
        Resource = ["${aws_s3_bucket.raw.arn}/*"]
      }]
    })
    sqs_send = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = ["sqs:SendMessage"],
        Effect = "Allow",
        Resource = [aws_sqs_queue.jobs.arn]
      }]
    })
  }
}

module "worker_task_role" {
  source = "./modules/iam-ecs-task-role"
  name   = "worker-task-role"
  policies = {
    s3_rw = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = ["s3:GetObject", "s3:PutObject"],
        Effect = "Allow",
        Resource = ["${aws_s3_bucket.raw.arn}/*"]
      }]
    })
    rekogn = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = ["rekognition:DetectLabels"],
        Effect = "Allow",
        Resource = ["*"]
      }]
    })
    sqs_delete = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = ["sqs:DeleteMessage"],
        Effect = "Allow",
        Resource = [aws_sqs_queue.jobs.arn]
      }]
    })
  }
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow ALB to web ECS"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    security_groups = [module.alb.security_group_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "worker" {
  name        = "worker-sg"
  description = "No ingress, only egress for worker ECS"
  vpc_id      = module.vpc.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "web" {
  source = "./modules/ecs-service"
  name   = "web"
  image  = var.web_image
  cpu    = 256
  memory = 512
  env    = {
    BUCKET    = aws_s3_bucket.raw.bucket
    QUEUE_URL = aws_sqs_queue.jobs.id
  }
  desired_count     = 2
  cluster_id        = module.cluster.cluster_id
  subnets           = module.vpc.private_subnets
  security_groups   = ["${aws_security_group.web.id}"]
  target_group_arn  = module.alb.target_groups["https-web-0"].arn
  listener_port     = 8080
  execution_role_arn = module.web_task_role.arn
  task_role_arn      = module.web_task_role.arn
}

module "worker" {
  source = "./modules/ecs-service"
  name   = "worker"
  image  = var.worker_image
  cpu    = 256
  memory = 512
  env    = {
    BUCKET     = aws_s3_bucket.raw.bucket
    QUEUE_NAME = aws_sqs_queue.jobs.name
  }
  desired_count      = 1
  cluster_id         = module.cluster.cluster_id
  subnets            = module.vpc.private_subnets
  security_groups    = ["${aws_security_group.worker.id}"]
  execution_role_arn = module.worker_task_role.arn
  task_role_arn      = module.worker_task_role.arn
}

module "alarms" {
  source       = "./modules/alarms"
  queue_name   = aws_sqs_queue.jobs.name
  cluster_name = module.cluster.cluster_name
  web_service  = module.web.name
}

# TODO: Add ALB module, ECS service modules, IAM roles 