variable "name" {}
variable "image" {}
variable "cpu" {}
variable "memory" {}
variable "env" { type = map(string) }
variable "assign_public_ip" { default = false }
variable "desired_count" { default = 1 }
variable "listener_arn" { default = null }
variable "listener_port" { default = null }
variable "autoscale_sqs_queue" { default = null }

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  container_definitions    = jsonencode([
    {
      name      = var.name
      image     = var.image
      essential = true
      portMappings = var.listener_port != null ? [{ containerPort = var.listener_port, hostPort = var.listener_port }] : []
      environment = [for k, v in var.env : { name = k, value = v }]
    }
  ])
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = var.subnets
    assign_public_ip = var.assign_public_ip
    security_groups  = var.security_groups
  }
  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.name
    container_port   = var.listener_port
  }
  depends_on = [aws_ecs_task_definition.this]
} 