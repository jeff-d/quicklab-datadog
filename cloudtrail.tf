# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


locals {
  create_cloudtrail = contains(var.autosubscribe_log_sources, "cloudtrail")
}

# Trail - scoped to this region's events
resource "aws_cloudtrail" "this" {
  count                         = local.create_cloudtrail ? 1 : 0
  depends_on                    = [aws_s3_bucket.trail, aws_s3_bucket_policy.trail]
  name                          = "${var.prefix}-${var.uid}-trail-${data.aws_region.current.region}"
  s3_bucket_name                = aws_s3_bucket.trail[0].id
  include_global_service_events = true
  is_multi_region_trail         = false
  is_organization_trail         = false
  insight_selector { insight_type = "ApiCallRateInsight" }
  insight_selector { insight_type = "ApiErrorRateInsight" }
  tags = merge(local.cloud_resource_tags, { Name = "${var.prefix}-${var.uid}-trail" })
}

# Bucket - store the logs
resource "aws_s3_bucket" "trail" {
  count         = local.create_cloudtrail ? 1 : 0
  bucket_prefix = "${var.prefix}-${var.uid}-cloudtrail-${data.aws_region.current.region}-"
  force_destroy = true
  tags = merge(local.cloud_resource_tags,
    {
      Name    = "${var.prefix}-${var.uid}-cloudtrail"
      service = "cloudtrail"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count  = local.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count  = local.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "default retention"
    status = "Enabled"
    expiration { days = 7 }
    filter {} # applies to all bucket objects
  }
}

# CloudTrail S3 Bucket Policy (enables CloudTrail to write to Bucket)
data "aws_iam_policy_document" "trail_bucket_policy" {
  count = local.create_cloudtrail ? 1 : 0
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count  = local.create_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket_policy[0].json
}

# Datadog IAM Policy (enables Datadog Integration Role to read bucket objects)
data "aws_iam_policy_document" "datadog_cloudtrail_policy" {
  count = local.create_cloudtrail ? 1 : 0
  statement {
    sid    = "DatadogCloudTrailS3"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      # "s3:GetObjectVersion",
      "s3:ListBucketVersions",
      "s3:ListBucket",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.trail[0].bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.trail[0].bucket}/*"
    ]
  }

  statement {
    sid    = "DatadogCloudTrailCT"
    effect = "Allow"
    actions = [
      "cloudtrail:DescribeTrails",
      "cloudtrail:GetTrailStatus",
    ]
    resources = ["${aws_cloudtrail.this[0].arn}"]
  }
}

resource "aws_iam_policy" "datadog_cloudtrail_policy" {
  count  = local.create_cloudtrail ? 1 : 0
  name   = "${var.prefix}-${var.uid}-${local.module}-cloudtrail-policy"
  path   = "/"
  policy = data.aws_iam_policy_document.datadog_cloudtrail_policy[0].json
  tags   = local.cloud_resource_tags
}

resource "aws_iam_role_policy_attachment" "datadog_cloudtrail_policy" {
  count = local.create_cloudtrail ? 1 : 0

  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = aws_iam_policy.datadog_cloudtrail_policy[0].arn
}
