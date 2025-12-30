# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


## Datadog AWS Integration
# https://docs.datadoghq.com/integrations/amazon-web-services/
# https://app.datadoghq.com/screen/integration/7/aws-overview

data "aws_iam_policy_document" "datadog_aws_integration_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::464622532012:root"] # Datadog AWS Account that assumes your cross-account Role
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values = [
        "${datadog_integration_aws_account.datadog_integration.auth_config.aws_auth_config_role.external_id}"
      ]
    }
  }
}

data "datadog_integration_aws_iam_permissions" "datadog_permissions" {}

locals {
  all_permissions = data.datadog_integration_aws_iam_permissions.datadog_permissions.iam_permissions

  max_policy_size   = 6144
  target_chunk_size = 5900

  permission_sizes = [
    for perm in local.all_permissions :
    length(perm) + 3
  ]
  cumulative_sizes = [
    for i in range(length(local.permission_sizes)) :
    sum(slice(local.permission_sizes, 0, i + 1))
  ]

  chunk_assignments = [
    for cumulative_size in local.cumulative_sizes :
    floor(cumulative_size / local.target_chunk_size)
  ]
  chunk_numbers = distinct(local.chunk_assignments)
  permission_chunks = [
    for chunk_num in local.chunk_numbers : [
      for i, perm in local.all_permissions :
      perm if local.chunk_assignments[i] == chunk_num
    ]
  ]
}

data "aws_iam_policy_document" "datadog_aws_integration" {
  count = length(local.permission_chunks)

  statement {
    actions   = local.permission_chunks[count.index]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "datadog_aws_integration" {
  count = length(local.permission_chunks)

  name   = "${var.prefix}-${var.uid}-DatadogAWSIntegrationPolicy-${count.index + 1}"
  policy = data.aws_iam_policy_document.datadog_aws_integration[count.index].json

  tags = local.cloud_resource_tags
}

resource "aws_iam_role" "datadog_aws_integration" {
  name               = "${var.prefix}-${var.uid}-DatadogIntegrationRole"
  description        = "Role for Datadog AWS Integration"
  assume_role_policy = data.aws_iam_policy_document.datadog_aws_integration_assume_role.json

  tags = local.cloud_resource_tags
}

resource "aws_iam_role_policy_attachment" "datadog_aws_integration" {
  count = length(local.permission_chunks)

  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = aws_iam_policy.datadog_aws_integration[count.index].arn
}

resource "aws_iam_role_policy_attachment" "datadog_aws_integration_security_audit" {
  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "datadog_integration_aws_account" "datadog_integration" {
  account_tags   = [for k, v in local.datadog_tags : "${k}:${v}"] # list(string) Tags to apply to all metrics in the account. 
  aws_account_id = var.aws_account_id
  aws_partition  = "aws"

  aws_regions {
    include_only = ["${var.aws_region}"] # alternative to the empty-block behavior 'include_all  = true'
  }

  auth_config {
    aws_auth_config_role {
      role_name = var.integration_role_name != "DatadogIntegrationRole" ? var.integration_role_name : "${var.prefix}-${var.uid}-DatadogIntegrationRole" #* using aws_iam_role.datadog_aws_integration.name gives a tf cycle error
    }
  }

  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = true # required for cloud_security_posture_management_collection
  }

  metrics_config {
    # automute_enabled          = true # default: true (ref: https://docs.datadoghq.com/integrations/amazon-ec2/?tab=awssystemsmanagerssm#ec2-automuting)
    # collect_cloudwatch_alarms = true  # default: false
    # collect_custom_metrics    = true  # default: false
    # enabled                   = true  # default: true

    namespace_filters {
      # include_only = []               # allowed values in data.datadog_integration_aws_available_namespaces.aws_namespaces
      # exclude_only = []               # defaults to ["AWS/SQS", "AWS/ElasticMapReduce", "AWS/Usage"] to reduce your AWS CloudWatch costs from GetMetricData API calls
    }

    tag_filters {
      #TODO: test using dynamic block here to cover multiple  namespace/tag combos
      namespace = "AWS/EC2"
      tags      = ["datadog:true"]
    }

  }

  logs_config {
    /*
    lambda_forwarder {
      lambdas = ["arn:aws:lambda:us-east-1:123456789012:function:my-lambda"] # supports multiple forwarder ARNs
      sources = ["s3"] # allowed values in data.datadog_integration_aws_available_logs_services.aws_log_services
      log_source_config {
        tag_filters {
        #TODO: test using dynamic block here to cover multiple source/tag combos
          source = "s3"
          tags   = ["env:prod", "team:backend"]
        }
    }
    */
  }

  traces_config {
    xray_services {
      # include_all = true (overrides xray_services empty block behavior for include_only)
      # include_only = [] # default: []
    }
  }
}


/*
#! Datadog S3 Policy (read bucket)
data "aws_iam_policy_document" "datadog_jmd_s3_policy" {
  statement {
    sid    = "EnrichmentTablesS3"
    effect = "Allow"

    resources = [
      "arn:aws:s3:::jmd-airlift/*",
      "arn:aws:s3:::jmd-airlift",
    ]

    actions = [
      "s3:GetObject",
      "kms:Decrypt",
      "s3:ListBucket",
    ]
  }
}
resource "aws_iam_policy" "datadog_jmd_s3_policy" {
  name   = "${var.prefix}-s3-policy"
  policy = data.aws_iam_policy_document.datadog_jmd_s3_policy.json
}
resource "aws_iam_role_policy_attachment" "datadog_jmd_s3_policy" {
  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = aws_iam_policy.datadog_jmd_s3_policy.arn
}

*/



