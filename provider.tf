# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

terraform {

  # required_version = "<= 1.5.7" #* latest version licensed under MPL 2.0
  required_version = "~> 1.12.0"

  # Declared, not configured: a child module states which providers it needs and inherits the
  # configuration from the root. Every provider this module uses must be listed here, or
  # Terraform infers it and the consumer gets an unconstrained version.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.15.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
