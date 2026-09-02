# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The basic build: the Datadog overlay with every QuickLab component switched off.
# This is what a standalone consumer gets by supplying only the required inputs, so
# these assertions are the module's minimum documented behavior.

# Only the providers that would reach a network are mocked. local and random compute
# locally and are used for real: mocking random is in fact not possible here, because
# module.datadog_secrets uses ephemeral.random_password and Terraform's mocking
# mechanism does not support ephemeral resource types.
mock_provider "aws" { source = "./tests/mocks/aws" }
mock_provider "datadog" { source = "./tests/mocks/datadog" }
mock_provider "helm" {}
mock_provider "http" { source = "./tests/mocks/http" }

variables {
  prefix = "quicklab"
  uid    = "ab12"

  # Valid in both Datadog's published site list and the forwarder module's own
  # allowlist, so no assertion here depends on the discrepancy between the two.
  # See readme.md "Terraform Implementation Details / tests".
  datadog_site = "datadoghq.com"
}

run "basic_build" {
  command = plan

  assert {
    condition = keys(datadog_api_key.this) == [
      "agent-installation", "log-forwarder", "workflow-automation",
    ]
    error_message = "A basic build should mint exactly the three baseline API keys, got: ${join(", ", keys(datadog_api_key.this))}"
  }

  assert {
    condition     = keys(datadog_application_key.this) == ["workflow-automation"]
    error_message = "A basic build should mint exactly one application key, got: ${join(", ", keys(datadog_application_key.this))}"
  }

  assert {
    condition     = length(datadog_app_key_registration.this) == length(datadog_application_key.this)
    error_message = "Every application key must be registered for use by Datadog Actions."
  }

  # Each key, api and app alike, gets exactly one Secrets Manager secret.
  assert {
    condition     = length(module.datadog_secrets) == 4
    error_message = "Expected 4 secrets (3 API keys + 1 app key), got ${length(module.datadog_secrets)}."
  }
}

run "basic_build_creates_no_component_resources" {
  command = plan

  assert {
    condition     = length(helm_release.datadog_operator) == 0
    error_message = "The Datadog Operator requires cluster_enabled."
  }

  assert {
    condition     = length(helm_release.cloudprem) == 0
    error_message = "CloudPrem requires both cluster_enabled and create_byoc_k8s_deployments."
  }

  assert {
    condition     = length(aws_s3_bucket.cloudprem) == 0
    error_message = "The CloudPrem bucket requires both cluster_enabled and create_byoc_k8s_deployments."
  }

  assert {
    condition     = length(aws_ssm_association.server_install) == 0
    error_message = "Agent installation requires create_server."
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 0
    error_message = "A trail is only created when \"cloudtrail\" is in autosubscribe_log_sources."
  }
}

# The AWS integration and cost reporting are not gated on any component flag: they are
# the overlay itself, and a basic build is expected to produce them.
run "basic_build_creates_the_integration" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.datadog_aws_integration) > 0
    error_message = "The cross-account integration policy should always be created."
  }

  assert {
    condition     = aws_iam_role.datadog_aws_integration.name == "quicklab-ab12-DatadogIntegrationRole"
    error_message = "Unexpected integration role name: ${aws_iam_role.datadog_aws_integration.name}"
  }
}

# Name lengths are asserted against AWS's hard limits rather than eyeballed. These fail
# only at apply otherwise, and prefix and uid are caller-supplied so the margin is not
# obvious from reading the expressions.
run "generated_names_fit_aws_limits" {
  command = plan

  assert {
    condition     = length(aws_iam_role.datadog_aws_integration.name) <= 64
    error_message = "IAM role names are limited to 64 characters."
  }

  assert {
    condition     = length(aws_iam_policy.datadog_actions.name) <= 128
    error_message = "IAM policy names are limited to 128 characters."
  }

  assert {
    condition     = alltrue([for p in aws_iam_policy.datadog_aws_integration : length(p.name) <= 128])
    error_message = "IAM policy names are limited to 128 characters."
  }

  assert {
    condition     = length(aws_s3_bucket.cur.bucket_prefix) <= 37
    error_message = "S3 bucket_prefix is limited to 37 characters so AWS can append a unique suffix within the 63-character bucket name limit."
  }
}
