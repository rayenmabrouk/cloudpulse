# ============================================================
# CloudPulse - Monitoring module
# Creates: CloudWatch log group, 5xx metric filter, three alarms
#          (instance status, CPU, HTTP 5xx), optional SNS email notifications
# ============================================================

resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_158:CloudWatch Logs encrypts log data at rest by default; a customer-managed key would add a key policy to maintain
  # checkov:skip=CKV_AWS_338:short retention chosen deliberately to limit cost in a lab environment
  name              = "/${var.project_name}/dpaste"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# --- Optional alarm notifications ---
# Created only when alarm_email is set. The subscription must be confirmed from the email.
resource "aws_sns_topic" "alarms" {
  # checkov:skip=CKV_AWS_26:CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed aws/sns key, and a customer-managed key is not worth its cost here; messages only contain alarm metadata
  count = var.alarm_email == "" ? 0 : 1
  name  = "${var.project_name}-alarms"

  tags = {
    Name = "${var.project_name}-alarms"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = aws_sns_topic.alarms[*].arn
}

# --- Instance health: EC2 system or instance status check failing ---
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.project_name}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 instance status check failed (hardware, network or OS problem)"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    InstanceId = var.instance_id
  }
}

# --- Capacity: sustained CPU on a burstable instance ---
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization above 80% for 10 minutes (a t3.micro will soon run out of CPU credits)"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    InstanceId = var.instance_id
  }
}

# --- Application health: HTTP 5xx answered by Caddy ---
# Caddy writes one JSON access-log line per request to the same log group.
# A 502 is what users get when the dpaste container is down or crashing, so this
# catches application failures that the EC2 status check cannot see.
resource "aws_cloudwatch_log_metric_filter" "http_5xx" {
  name           = "${var.project_name}-http-5xx"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.status >= 500 }"

  metric_transformation {
    name          = "Http5xxCount"
    namespace     = "CloudPulse"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.project_name}-http-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.http_5xx.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.http_5xx.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching" # no traffic is not an error
  alarm_description   = "5 or more HTTP 5xx responses in 5 minutes (502 = dpaste container down behind Caddy)"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
