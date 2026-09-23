# ============================================================
# CloudPulse - Monitoring Module
# Creates: CloudWatch log group, CPU alarm, status check alarm
# ============================================================

resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_158:CloudWatch Logs encrypts log data at rest by default; a customer-managed key would add a key policy to maintain
  # checkov:skip=CKV_AWS_338:7-day retention chosen deliberately to limit cost in a lab environment
  name              = "/cloudpulse/dpaste"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-logs"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization exceeds 80% for 10 minutes"

  dimensions = {
    InstanceId = var.instance_id
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.project_name}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 instance status check failed"

  dimensions = {
    InstanceId = var.instance_id
  }
}
