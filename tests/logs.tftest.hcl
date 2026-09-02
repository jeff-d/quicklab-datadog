# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Log and metric collection, which is where this module's two silent-failure modes live:
# autosubscribe_log_sources and local.include_metric_namespaces are both intersected
# against a live Datadog data source, so an entry the API does not recognize is dropped
# without any error. A caller only finds out when the telemetry never arrives.

mock_provider "aws" { source = "./tests/mocks/aws" }
mock_provider "datadog" { source = "./tests/mocks/datadog" }
mock_provider "helm" {}
mock_provider "http" { source = "./tests/mocks/http" }

variables {
  prefix       = "quicklab"
  uid          = "ab12"
  datadog_site = "datadoghq.com"
}

# A note on the tolist() wrapping below. The provider types these attributes as
# list(string), while an HCL literal like ["cloudtrail"] is a tuple, and Terraform's ==
# reports "LHS and RHS values are of different types" rather than comparing element-wise.
# Converting both sides is what makes the comparison meaningful.

run "no_log_sources_creates_no_trail" {
  command = plan

  variables {
    autosubscribe_log_sources = []
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 0
    error_message = "No trail should be created when cloudtrail is not an autosubscribed source."
  }

  assert {
    condition     = length(aws_s3_bucket.trail) == 0
    error_message = "No trail bucket should be created when cloudtrail is not an autosubscribed source."
  }

  assert {
    condition     = length(datadog_integration_aws_account.datadog_integration.logs_config.lambda_forwarder.sources) == 0
    error_message = "The forwarder should subscribe to no log sources by default."
  }
}

# The trail is a side effect of naming "cloudtrail" as a log source; there is no separate
# flag for it. Other sources are subscriptions to logs AWS already emits.
run "cloudtrail_source_creates_a_trail" {
  command = plan

  variables {
    autosubscribe_log_sources = ["cloudtrail", "elbv2", "vpc"]
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 1
    error_message = "Naming cloudtrail as a log source should create the trail that produces those logs."
  }

  assert {
    condition = tolist(datadog_integration_aws_account.datadog_integration.logs_config.lambda_forwarder.sources) == tolist([
      "cloudtrail", "elbv2", "vpc",
    ])
    error_message = "All three recognized sources should reach the integration."
  }

  assert {
    condition     = length(aws_s3_bucket.trail) == 1
    error_message = "The trail needs a bucket to deliver into."
  }
}

run "other_log_sources_create_no_trail" {
  command = plan

  variables {
    autosubscribe_log_sources = ["elbv2", "vpc"]
  }

  assert {
    condition     = length(aws_cloudtrail.this) == 0
    error_message = "Only the cloudtrail source implies a trail."
  }
}

# Pins the silent drop in aws-integration.tf: sources are filtered against
# data.datadog_integration_aws_available_logs_services, so a typo or a service Datadog
# has renamed disappears from the subscription with no error anywhere.
run "unrecognized_log_sources_are_dropped_silently" {
  command = plan

  variables {
    autosubscribe_log_sources = ["cloudtrail", "not-a-real-service"]
  }

  assert {
    condition     = tolist(datadog_integration_aws_account.datadog_integration.logs_config.lambda_forwarder.sources) == tolist(["cloudtrail"])
    error_message = "Sources absent from the Datadog API's list should be filtered out, got: ${join(", ", datadog_integration_aws_account.datadog_integration.logs_config.lambda_forwarder.sources)}"
  }

  # The trail is gated on the raw input rather than the filtered list, so an
  # unrecognized neighbor does not suppress it.
  assert {
    condition     = length(aws_cloudtrail.this) == 1
    error_message = "An unrecognized sibling source should not suppress the trail."
  }
}

# Whereas the sources filter drops unknown values, the tag_filters block iterates the raw
# input. This asymmetry is intentional but easy to break, so it is pinned here.
run "log_source_tag_filters_use_the_unfiltered_input" {
  command = plan

  variables {
    autosubscribe_log_sources = ["cloudtrail", "not-a-real-service"]
  }

  assert {
    condition     = length(datadog_integration_aws_account.datadog_integration.logs_config.lambda_forwarder.log_source_config.tag_filters) == 2
    error_message = "tag_filters iterates var.autosubscribe_log_sources directly, so it should carry both entries."
  }
}

# The metric namespace list is a hardcoded local intersected against the same kind of
# live data source. The mock advertises exactly local.include_metric_namespaces, so the
# healthy case is that nothing is dropped.
run "all_intended_metric_namespaces_survive_the_filter" {
  command = plan

  assert {
    condition = length(datadog_integration_aws_account.datadog_integration.metrics_config.namespace_filters.include_only) == length(
      data.datadog_integration_aws_available_namespaces.all.aws_namespaces
    )
    error_message = "Every namespace the module intends to collect should reach the integration when Datadog advertises it."
  }

  assert {
    condition     = contains(datadog_integration_aws_account.datadog_integration.metrics_config.namespace_filters.include_only, "AWS/EC2")
    error_message = "AWS/EC2 is a baseline namespace and should always be collected."
  }
}

# The other side of the same filter: when Datadog stops advertising a namespace the
# module asks for, it vanishes from include_only rather than raising an error.
run "unavailable_metric_namespaces_are_dropped_silently" {
  command = plan

  override_data {
    target = data.datadog_integration_aws_available_namespaces.all
    values = {
      aws_namespaces = ["AWS/EC2", "AWS/Lambda"]
    }
  }

  assert {
    # Ordering follows local.include_metric_namespaces, where AWS/Lambda precedes AWS/EC2,
    # rather than the order the data source advertises them in.
    condition = tolist(datadog_integration_aws_account.datadog_integration.metrics_config.namespace_filters.include_only) == tolist([
      "AWS/Lambda", "AWS/EC2",
    ])
    error_message = "Only namespaces the API advertises should reach the integration, got: ${join(", ", datadog_integration_aws_account.datadog_integration.metrics_config.namespace_filters.include_only)}"
  }
}
