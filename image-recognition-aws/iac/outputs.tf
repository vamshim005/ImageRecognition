output "sqs_queue_url" {
  value = aws_sqs_queue.jobs.id
}

output "vpc_id" {
  value = module.vpc.vpc_id
} 