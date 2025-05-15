provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
  name   = "img-recognition-vpc"
  cidr   = "10.0.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = true
  
  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.8.0"
  
  cluster_name = "imgrec-cluster"
  
  cluster_configuration = {
    execute_command_configuration = {
      logging = "OVERRIDE"
      log_configuration = {
        cloud_watch_log_group_name = "/aws/ecs/imgrec-cluster"
      }
    }
  }

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
        base   = 1
      }
    }
  }
}

resource "aws_sqs_queue" "jobs" {
  name                      = "image-jobs"
  visibility_timeout_seconds = 30
  kms_master_key_id         = "alias/aws/sqs"
}

resource "aws_s3_bucket" "raw" {
  bucket = "imgrec-raw-${var.project_id}"
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = "alias/aws/s3"
      sse_algorithm     = "aws:kms"
    }
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "8.7.0"
  name    = "imgrec"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  enable_http2       = true

  security_group_rules = {
    ingress_all_http = {
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "HTTP web traffic"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_all_https = {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS web traffic"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = var.acm_cert_arn
      target_group_index = 0
    }
  ]

  target_groups = [
    {
      name_prefix      = "web-"
      backend_protocol = "HTTP"
      backend_port     = 8080
      target_type      = "ip"
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 6
        protocol            = "HTTP"
        matcher             = "200-399"
      }
    }
  ]
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
  target_group_arn  = module.alb.target_group_arns[0]
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
  web_service  = module.web.service_name
}

# TODO: Add ALB module, ECS service modules, IAM roles 