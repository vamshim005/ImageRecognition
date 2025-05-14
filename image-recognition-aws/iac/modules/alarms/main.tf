variable "queue_name" {}
variable "cluster_name" {}
variable "web_service" {}

resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  alarm_name          = "SQS-Depth>100"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 100
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  statistic           = "Sum"
  dimensions          = { QueueName = var.queue_name }
}

resource "aws_cloudwatch_metric_alarm" "cpu_web" {
  alarm_name          = "ECS-Web-CPU>75"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 75
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  statistic           = "Average"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.web_service }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "imgrec-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.queue_name]]
          title   = "Queue depth"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [["AWS/ECS", "CPUUtilization", "ServiceName", var.web_service, "ClusterName", var.cluster_name]]
          title   = "Web CPU %"
        }
      }
    ]
  })
} 