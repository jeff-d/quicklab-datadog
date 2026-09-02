# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The module's input contract: what it accepts and, more importantly, what it refuses.
#
# When called from QuickLab, the caller's own validations screened every input, 
# but a direct consumer gets no such screening, so each validation here is the
# only thing standing between a bad value and a confusing failure deep inside a submodule.

mock_provider "aws" { source = "./tests/mocks/aws" }
mock_provider "datadog" { source = "./tests/mocks/datadog" }
mock_provider "helm" {}
mock_provider "http" { source = "./tests/mocks/http" }

variables {
  prefix       = "quicklab"
  uid          = "ab12"
  datadog_site = "datadoghq.com"
}

## datadog_site
#
# The input is the Datadog *site parameter* in domain form, the DD_SITE convention, and
# all eight call sites consume it that way: DD_SITE for the forwarder and the cost
# manager, DATADOG_SITE for CloudPrem and the Agent manifest, site for the Operator and
# the SSM installation documents, and base_url = "https://api.${var.datadog_site}" for
# the Actions connection.
#
# The region code is the obvious wrong guess, since that is the label the Datadog UI and
# most of its documentation put in front of a user. Passing US1 did already fail before
# this validation existed, but only from inside the third-party forwarder submodule, and
# only on the forwarder path: the Agent, Operator, and CloudPrem paths would have gone on
# to build URLs like https://api.US1 and failed at runtime instead.

run "rejects_a_region_code_in_place_of_a_site" {
  command = plan

  variables {
    datadog_site = "US1"
  }

  expect_failures = [var.datadog_site]
}

run "rejects_a_site_domain_that_does_not_exist" {
  command = plan

  # Plausible-looking and wrong: Datadog publishes datadoghq.eu and us3.datadoghq.com,
  # but no us3.datadoghq.eu. A shape-matching regex would have accepted this, which is
  # why the validation is a closed set of the nine published parameters instead.
  variables {
    datadog_site = "us3.datadoghq.eu"
  }

  expect_failures = [var.datadog_site]
}

run "accepts_a_published_site_parameter" {
  command = plan

  variables {
    datadog_site = "us3.datadoghq.com"
  }

  assert {
    condition     = length(aws_iam_role.datadog_aws_integration.name) > 0
    error_message = "A published site parameter should plan cleanly."
  }
}

# Deliberately not tested: uk1.datadoghq.com and us2.ddog-gov.com. Datadog publishes both
# and this module's validation accepts both, but the forwarder submodule carries its own
# stale dd_site allowlist that omits them, and module "datadog_forwarder" is ungated, so
# a plan with either site fails inside a dependency. That gap is being raised upstream.
# Asserting on it here would couple this repository's CI to a third-party fix, and the
# escape hatch that would work around it, skip_dd_site_validation, is marked
# internal-use-only upstream.

## server_os

run "rejects_an_unsupported_server_os" {
  command = plan

  variables {
    create_server = true
    server_os     = ["macos"]
  }

  expect_failures = [var.server_os]
}

# The original condition, can(contains([...], var.server_os)), was vacuous: contains()
# returns false on a type mismatch rather than raising, so can() saw no error and the
# validation passed for every input including this one.
run "rejects_an_unsupported_os_alongside_a_supported_one" {
  command = plan

  variables {
    create_server = true
    server_os     = ["linux", "macos"]
  }

  expect_failures = [var.server_os]
}

run "rejects_a_case_variant_of_a_supported_os" {
  command = plan

  variables {
    create_server = true
    server_os     = ["Linux"]
  }

  expect_failures = [var.server_os]
}

run "accepts_both_supported_operating_systems" {
  command = plan

  variables {
    create_server = true
    server_os     = ["linux", "windows"]
  }

  assert {
    condition     = length(aws_ssm_association.server_install) == 2
    error_message = "Both supported operating systems should be accepted."
  }
}

## cloudprem_retention
#
# The value drives an S3 lifecycle expiration as well as the CloudPrem index setting, and
# a lifecycle expiration of zero days deletes objects as soon as they land.

run "rejects_zero_cloudprem_retention" {
  command = plan

  variables {
    cloudprem_retention = 0
  }

  expect_failures = [var.cloudprem_retention]
}

run "rejects_negative_cloudprem_retention" {
  command = plan

  variables {
    cloudprem_retention = -1
  }

  expect_failures = [var.cloudprem_retention]
}

## Required and optional inputs
#
# datadog_site is the module's only required input. Everything else has a default, and
# this run is what proves it: it sets nothing but prefix, uid, and the site.

run "datadog_site_is_the_only_required_input" {
  command = plan

  assert {
    condition     = length(datadog_api_key.this) == 3
    error_message = "The module should plan with no inputs beyond prefix, uid, and datadog_site."
  }
}
