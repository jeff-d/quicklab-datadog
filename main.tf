# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  module              = "datadog"
  cloud_resource_tags = merge(var.cloud_resource_tags, {})
  datadog_tags        = merge(var.datadog_tags, {})
  datadog_secrets = {
    api_keys = ["agent-installation", "workflow-automation"] # "forwarder" #! module.datadog_forwarder creates its own key
    app_keys = ["workflow-automation"]
  }
}

resource "datadog_api_key" "this" {
  for_each                   = toset(local.datadog_secrets.api_keys)
  name                       = "${var.prefix}-${var.uid}-${each.value}"
  remote_config_read_enabled = true
}

resource "datadog_application_key" "this" {
  for_each = toset(local.datadog_secrets.app_keys)
  name     = "${var.prefix}-${var.uid}-${each.value}"

  # add scopes to restrict user permissions
  # scopes = [] 
}

resource "datadog_app_key_registration" "this" {
  for_each = toset(local.datadog_secrets.app_keys)
  id       = datadog_application_key.this[each.value].id
}

module "datadog_secrets" {
  for_each = merge(
    { for name in local.datadog_secrets.api_keys : "api-key-${name}" => name },
    { for name in local.datadog_secrets.app_keys : "app-key-${name}" => name }
  )
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 2.1.0"

  name                    = "${var.prefix}-${var.uid}-${local.module}-${each.key}"
  description             = "Datadog ${startswith(each.key, "app-key") ? "Application" : "API"} Key: ${each.value}"
  recovery_window_in_days = 0
  secret_string           = startswith(each.key, "app-key") ? datadog_application_key.this[each.value].key : datadog_api_key.this[each.value].key
  block_public_policy     = true
  source_policy_documents = [data.aws_iam_policy_document.secret_resource_policy.json]

  tags = { Name = "${var.prefix}-${var.uid}-${local.module}-${each.key}-secret" }
}

data "aws_iam_policy_document" "secret_resource_policy" {
  statement {
    sid    = "EnableActionConnectionToReadSecrets"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.datadog_aws_integration.arn]
    }

    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.prefix}-${var.uid}-${local.module}*"]
  }
}




