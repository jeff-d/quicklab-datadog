# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


# S3 bucket for CURs
resource "aws_s3_bucket" "cur" {
  bucket_prefix = "${var.prefix}-${var.uid}-cur-${data.aws_region.current.region}-"
  force_destroy = true
  tags = merge(local.cloud_resource_tags,
    {
      Name = "${var.prefix}-${var.uid}-cost-reporting"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket = aws_s3_bucket.cur.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    # CUR writes with bucket-owner-full-control ACL; keep ACLs enabled.
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    id     = "default retention"
    status = "Enabled"
    expiration { days = 7 }
    filter {} # applies to all bucket objects
  }
}


# Bucket policy to allow CUR and BCM Data Exports services to write reports                                             
resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "billingreports.amazonaws.com",
            "bcm-data-exports.amazonaws.com"
          ]
        }
        Action = [
          "s3:PutObject",
          "s3:GetBucketPolicy"
        ]
        Resource = [
          aws_s3_bucket.cur.arn,
          "${aws_s3_bucket.cur.arn}/*"
        ]
        Condition = {
          StringLike = {
            "aws:SourceArn" = [
              "arn:*:cur:*:${data.aws_caller_identity.current.account_id}:definition/*",
              "arn:*:bcm-data-exports:*:${data.aws_caller_identity.current.account_id}:export/*"
            ]
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}


# CUR definition
resource "aws_cur_report_definition" "datadog_cur" {
  additional_artifacts       = []
  additional_schema_elements = ["RESOURCES", "SPLIT_COST_ALLOCATION_DATA"]
  compression                = "Parquet"
  format                     = "Parquet"
  refresh_closed_reports     = true
  report_name                = "${var.prefix}-${var.uid}-${local.module}-costreport"
  report_versioning          = "CREATE_NEW_REPORT"
  s3_bucket                  = aws_s3_bucket.cur.bucket
  s3_prefix                  = "${local.module}/costreport"
  s3_region                  = data.aws_region.current.region
  time_unit                  = "HOURLY"
  depends_on                 = [aws_s3_bucket.cur, aws_s3_bucket_policy.cur, aws_s3_bucket_public_access_block.cur, aws_s3_bucket_ownership_controls.cur]
  tags = merge(local.cloud_resource_tags,
    {
      Name = "${var.prefix}-${var.uid}-${local.module}-costreport"
    }
  )
}


# IAM policy for Datadog to access CUR data   
resource "aws_iam_policy" "datadog_cur_access" {
  name        = "${var.prefix}-${var.uid}-${local.module}-DatadogCURAccess-policy"
  description = "Allow Datadog to access Cost and Usage Reports"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DDCloudCostReadBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.cur.arn
      },
      {
        Sid    = "DDCloudCostGetBill"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.cur.arn}/${aws_cur_report_definition.datadog_cur.s3_prefix}/${aws_cur_report_definition.datadog_cur.report_name}/*"
      },
      {
        Sid    = "DDCloudCostCheckAccuracy"
        Effect = "Allow"
        Action = [
          "ce:Get*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DDCloudCostListCURs"
        Effect = "Allow"
        Action = [
          "cur:DescribeReportDefinitions"
        ]
        Resource = "*"
      },
      {
        Sid    = "DDCloudCostListOrganizations"
        Effect = "Allow"
        Action = [
          "organizations:Describe*",
          "organizations:List*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to an existing Datadog IAM role  
resource "aws_iam_role_policy_attachment" "datadog_cur_access" {
  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = aws_iam_policy.datadog_cur_access.arn
}

# Create new aws_cur_config resource
resource "datadog_aws_cur_config" "aws_cur_770341584863" {
  account_id    = data.aws_caller_identity.current.account_id
  bucket_name   = aws_s3_bucket.cur.bucket
  bucket_region = data.aws_region.current.region
  report_name   = aws_cur_report_definition.datadog_cur.report_name
  report_prefix = aws_cur_report_definition.datadog_cur.s3_prefix

  depends_on = [aws_cur_report_definition.datadog_cur, aws_iam_policy.datadog_cur_access]
}
