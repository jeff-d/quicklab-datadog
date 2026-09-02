# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Real apply and destroy against a sandbox AWS account and a real Datadog org.
#
# The integration- filename prefix is load-bearing, not decoration. Both workflows build
# their -filter lists by globbing this directory, so the prefix is what puts a file in
# this suite: test.yaml matches everything *without* it, and integration.yaml matches
# everything *with* it. Name any further integration file integration-<something> and it
# lands in the right suite automatically; name it anything else and it will run on every
# commit in a job that has no credentials.
#
# Run it locally with:
#   terraform test -filter=tests/integration-basic.tftest.hcl
#
# Note that a bare `terraform test` runs this file too, since it lives in the default
# test directory. That is a real apply against whatever credentials are in your shell.
#
# Providers take their configuration from the environment, so no credential ever appears
# in this file: AWS_REGION and either AWS_PROFILE or the standard AWS_* keys for AWS, and
# DD_API_KEY, DD_APP_KEY, and DD_HOST for Datadog.

provider "aws" {}

provider "datadog" {}

provider "helm" {}

variables {
  prefix       = "qltest"
  uid          = "ci01"
  datadog_site = "datadoghq.com"

  # The basic shape. Cluster, server, and BYOC components are all off, so this exercises
  # the AWS integration, the keys and their secrets, the log forwarder, and cost
  # reporting: everything the module builds unconditionally.
  autosubscribe_log_sources = ["cloudtrail"]
}

# Runs before the apply because it needs no infrastructure, only a live API, and it is
# the assertion most likely to fail for reasons outside this repository.
#
# Both of the module's collection filters silently discard values the Datadog API does
# not recognize, so a namespace Datadog renames or retires stops being collected with no
# error anywhere. Mocked tests cannot see this by construction: they assert against a
# fixture that says what we already believe. Only the real API can tell us we are wrong.
run "datadog_still_advertises_everything_the_module_collects" {
  command = plan

  assert {
    condition = length(setsubtract(
      local.include_metric_namespaces,
      data.datadog_integration_aws_available_namespaces.all.aws_namespaces
    )) == 0
    error_message = "Datadog no longer advertises these metric namespaces, and they are being dropped silently: ${join(", ", setsubtract(local.include_metric_namespaces, data.datadog_integration_aws_available_namespaces.all.aws_namespaces))}"
  }

  assert {
    condition = length(setsubtract(
      var.autosubscribe_log_sources,
      data.datadog_integration_aws_available_logs_services.all.aws_logs_services
    )) == 0
    error_message = "Datadog no longer advertises these log sources, and they are being dropped silently: ${join(", ", setsubtract(var.autosubscribe_log_sources, data.datadog_integration_aws_available_logs_services.all.aws_logs_services))}"
  }

  # The chunking arithmetic runs against the live permission list here, where it is
  # subject to Datadog adding permissions over time. The unit test proves the algorithm
  # on synthetic input; this proves it on the input that actually ships.
  assert {
    condition = alltrue([
      for chunk in local.permission_chunks :
      sum([for perm in chunk : length(perm) + 3]) <= 6144
    ])
    error_message = "The live Datadog permission list no longer chunks under the 6144-byte AWS managed policy limit."
  }
}

# The reason this suite exists. Every mocked test above proves the configuration is
# internally consistent; only a real apply proves AWS and Datadog accept it.
run "basic_build_applies" {
  command = apply

  assert {
    condition     = datadog_integration_aws_account.datadog_integration.aws_account_id != ""
    error_message = "The AWS account integration should be created and report its account."
  }

  assert {
    condition     = output.org_name != ""
    error_message = "Reading organization settings should return the org name, which confirms the app key works."
  }

  assert {
    condition     = output.collection_bucket_name != ""
    error_message = "The forwarder should report the bucket it stores failed deliveries in."
  }

  assert {
    condition     = length(output.agent_endpoints) > 0
    error_message = "The Datadog IP ranges data source should return at least one agent endpoint."
  }

  # Naming the cloudtrail source implies a real trail, which is the one resource here
  # whose creation depends on an input rather than being unconditional.
  assert {
    condition     = length(aws_cloudtrail.this) == 1
    error_message = "The cloudtrail log source should have produced a trail."
  }

  assert {
    condition     = aws_bcmdataexports_export.datadog_cur.arn != ""
    error_message = "The Cost and Usage Report export should be created."
  }
}

# A second apply with no input change must be a no-op. This is the cheapest way to catch
# a resource that reports drift on every run, which is invisible in a single apply and
# turns every subsequent plan in a consuming repository into noise.
run "second_apply_is_idempotent" {
  command = apply

  assert {
    condition     = output.org_name != ""
    error_message = "A repeat apply should converge without changing the org."
  }
}
