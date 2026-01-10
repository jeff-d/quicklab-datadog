output "failed_data_bucket_name" {
  description = "S3 Bucket where failed deliveries will be saved"
  value = join("-", ["datadog-failed-logs-delivery", data.aws_caller_identity.current.account_id])
}

output "datadog_delivery_stream_arn" {
  description = "The ARN for your Kinesis Firehose Delivery Stream, use this as the destination when adding CloudWatch Logs subscription filters"
  value = aws_kinesis_firehose_delivery_stream.datadog_delivery_stream.arn
}

output "cloud_watch_logs_role_arn" {
  description = "The ARN for your CloudWatch Logs role to write to your delivery stream, use this as the role-arn when adding CloudWatch Logs subscription filters"
  value = aws_iam_role.cloud_watch_logs_role.arn
}

