# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

terraform {

  # required_version = "<= 1.5.7" #* latest version licensed under MPL 2.0
  required_version = "~> 1.12.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.15.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    # Declared, not configured: a child module states which providers it needs and inherits the
    # configuration from the root. helm_release.cloudprem and helm_release.datadog_operator were
    # already relying on implicit inference, which left this constraint unexpressed.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.0"
    }
  }
}
