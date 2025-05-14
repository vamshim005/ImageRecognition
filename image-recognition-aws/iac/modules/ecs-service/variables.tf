variable "cluster_id" {}
variable "subnets" { type = list(string) }
variable "security_groups" { type = list(string) }
variable "target_group_arn" { default = null }
variable "execution_role_arn" {}
variable "task_role_arn" {}

output "service_arn" {
  value = aws_ecs_service.this.arn
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
} 