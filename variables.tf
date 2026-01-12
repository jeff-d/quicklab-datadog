# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

variable "prefix" {
  type        = string
  description = "A prefix to prepend to all resource names."
  default     = null
}

variable "uid" {
  type        = string
  description = "QuickLab ID"
  default     = null
}

variable "datadog_api_key" { type = string }

variable "datadog_app_key" { type = string }

variable "datadog_site" { type = string }

variable "cloud_resource_tags" {
  description = "A map of tags to add to all clous resources"
  type        = map(string)
  default     = {}
}

variable "datadog_tags" {
  description = "A map of tags to add to all Datadog resources and collected telemetry."
  type        = map(string)
  default     = {}
}

variable "integration_role_name" {
  type        = string
  description = "The name of the cross-account IAM role used for the Datadog AWS Account integration."
  default     = "DatadogIntegrationRole"
}

variable "server_os" {
  type        = list(string)
  description = "A flag to set the operating system the Quicklab server(s)"
  default     = []
  validation {
    condition     = can(contains(["linux", "windows"], var.server_os))
    error_message = "These list items must be \"linux\" and/or \"windows\" (case-sensitive)."
  }
}
