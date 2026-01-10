resource "aws_cloudwatch_log_stream" "delivery_stream_log_stream" {
  log_group_name = aws_cloudwatch_log_group.delivery_stream_log_group.arn
  name           = local.stack_name
}

resource "aws_cloudwatch_log_group" "delivery_stream_log_group" {}

resource "aws_s3_bucket" "failed_data_bucket" {
  // CF Property(PublicAccessBlockConfiguration) = {
  //   BlockPublicAcls = true
  //   BlockPublicPolicy = true
  //   IgnorePublicAcls = true
  //   RestrictPublicBuckets = true
  // }
  bucket = join("-", ["datadog-failed-logs-delivery", data.aws_caller_identity.current.account_id])
  acl    = "private"
}

resource "aws_iam_role" "cloud_watch_logs_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          Service = join("", ["logs.", data.aws_region.current.name, ".amazonaws.com"])
        }
        Action = "sts:AssumeRole"
      }
    ]
  }
}

resource "aws_iam_policy" "cloud_watch_logs_policy" {
  name = join("-", ["cloudwatch-firehose-policy", local.stack_name])
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch",
          "kinesis:PutRecord",
          "kinesis:PutRecordBatch"
        ]
        Resource = [
          join("", ["arn:aws:firehose:", data.aws_region.current.name, ":", data.aws_caller_identity.current.account_id, ":*"])
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          join("", ["arn:aws:iam::", data.aws_caller_identity.current.account_id, ":role/", aws_iam_role.cloud_watch_logs_role.arn])
        ]
      }
    ]
  }
  // CF Property(Roles) = [
  //   aws_iam_role.cloud_watch_logs_role.arn
  // ]
}

resource "aws_iam_role" "firehose_logs_role" {
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  }
}

resource "aws_iam_policy" "firehose_logs_policy" {
  name = join("-", ["datadog-firehose-delivery-policy", local.stack_name])
  policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          join("", ["arn:aws:s3:::", aws_s3_bucket.failed_data_bucket.id]),
          join("", ["arn:aws:s3:::", aws_s3_bucket.failed_data_bucket.id, "*"])
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          join("", ["arn:aws:logs:", data.aws_caller_identity.current.account_id, ":log-group:/aws/kinesisfirehose/", local.stack_name, ":log-stream:*"])
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.datadog_delivery_stream.arn
      }
    ]
  }
  // CF Property(Roles) = [
  //   aws_iam_role.firehose_logs_role.arn
  // ]
}

resource "aws_kinesis_firehose_delivery_stream" "datadog_delivery_stream" {
  name        = "foo"
  destination = "bar"
  // CF Property(DeliveryStreamType) = "DirectPut"
  http_endpoint_configuration {
    url      = "baz"
    role_arn = aws_iam_role.firehose_logs_role.arn
    s3_configuration {
      bucket_arn         = join("", ["arn:aws:s3:::", aws_s3_bucket.failed_data_bucket.id])
      compression_format = "UNCOMPRESSED"
      prefix             = var.failed_log_delivery_prefix
      role_arn           = aws_iam_role.firehose_logs_role.arn
    }
    request_configuration {
      content_encoding = "GZIP"
    }
    cloudwatch_logging_options {
      // CF Property(DurationInSeconds) = 60
    }
    // CF Property(BufferingHints) = {
    //   IntervalInSeconds = 60
    //   SizeInMBs = 4
    // }
    s3_backup_mode = "FailedDataOnly"
  }
}

