# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Pinned so resource names are deterministic. Account, region, and partition all feed
# name expressions that the unit tests assert length limits against; left to the mock
# provider's generated values those names would vary run to run.

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:role/quicklab-ci"
    user_id    = "AIDACKCEVSQ6C2EXAMPLE"
    id         = "123456789012"
  }
}

mock_data "aws_region" {
  defaults = {
    region      = "us-east-1"
    name        = "us-east-1"
    id          = "us-east-1"
    description = "US East (N. Virginia)"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition          = "aws"
    dns_suffix         = "amazonaws.com"
    id                 = "aws"
    reverse_dns_prefix = "com.amazonaws"
  }
}

# CloudPrem's security group module splits and validates this CIDR, so a generated
# random string fails the plan rather than merely producing an odd value.
mock_data "aws_vpc" {
  defaults = {
    id         = "vpc-0123456789abcdef0"
    cidr_block = "10.0.0.0/16"
  }
}

mock_data "aws_subnets" {
  defaults = {
    ids = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0bbbbbbbbbbbbbbb2"]
  }
}

# aws_iam_policy validates that its policy argument parses as a JSON object, so the
# generated random string the mock would otherwise supply fails the plan outright.
# Policy *content* is deliberately not asserted anywhere: the interesting logic is the
# permission chunking, which tests/iam.tftest.hcl checks against local.permission_chunks
# before it ever reaches a policy document.
mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}
