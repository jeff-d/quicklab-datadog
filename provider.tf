# This file is part of QuickLab, which creates simple, monitored labs.
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
      version = "~> 3.83.0"
    }
  }
}
