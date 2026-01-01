# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


# Trail - scoped to this region's events
resource "aws_cloudtrail" "this" {
  depends_on                    = [aws_s3_bucket.trail, aws_s3_bucket_policy.trail]
  name                          = "${var.prefix}-${var.uid}-trail-${data.aws_region.current.region}"
  s3_bucket_name                = aws_s3_bucket.trail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  is_organization_trail         = false
  insight_selector { insight_type = "ApiCallRateInsight" }
  insight_selector { insight_type = "ApiErrorRateInsight" }
  tags = merge(local.cloud_resource_tags, { Name = "${var.prefix}-${var.uid}-trail" })
}

# Bucket - store the logs
resource "aws_s3_bucket" "trail" {
  bucket_prefix = "${var.prefix}-${var.uid}-ct-${data.aws_region.current.region}-"
  force_destroy = true
  tags          = merge(local.cloud_resource_tags, { Name = "${var.prefix}-${var.uid}-cloudtrail" })
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "default retention"
    status = "Enabled"
    expiration { days = 7 }
    filter {} # applies to all bucket objects
  }
}

# CloudTrail S3 Bucket Policy (enables CloudTrail to write to Bucket)
data "aws_iam_policy_document" "trail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket_policy.json
}

# Datadog IAM Policy (enables Datadog Integration Role to read bucket objects)
data "aws_iam_policy_document" "datadog_cloudtrail_policy" {
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
      "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.trail.bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.trail.bucket}/*"
    ]
  }

  statement {
    sid    = "DatadogCloudTrailCT"
    effect = "Allow"
    actions = [
      "cloudtrail:DescribeTrails",
      "cloudtrail:GetTrailStatus",
    ]
    resources = ["${aws_cloudtrail.this.arn}"]
  }
}

resource "aws_iam_policy" "datadog_cloudtrail_policy" {
  name   = "${var.prefix}-${var.uid}-${local.module}-cloudtrail-policy"
  path   = "/"
  policy = data.aws_iam_policy_document.datadog_cloudtrail_policy.json
  tags   = local.cloud_resource_tags
}

resource "aws_iam_role_policy_attachment" "datadog_cloudtrail_policy" {

  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = aws_iam_policy.datadog_cloudtrail_policy.arn
}
