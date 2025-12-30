# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

variable "datadog_api_key" { type = string }

variable "datadog_app_key" { type = string }

variable "cloud_resource_tags" {
  description = "A map of tags to add to all clous resources"
  type        = map(string)
  default     = {}
}

variable "datadog_tags" {
  description = "A map of tags to add to all Datadog resources"
  type        = map(string)
  default     = {}
}

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

variable "aws_account_id" {
  type        = string
  description = "AWS Account ID in which to configure the Datadog Integration"
  default     = null
}

variable "aws_region" {
  type        = string
  description = "AWS Region that scopes data collection for the Datadog AWS Integration"
  default     = null
}

variable "integration_role_name" {
  type        = string
  description = "The name of the cross-account IAM role used for the Datadog AWS Account integration."
  default     = "DatadogIntegrationRole"
}

/*

#! UNUSED

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = object({ datadog_tags = map(string), cloud_resource_tags = map(string) })
  default = {
    datadog_tags        = {}
    cloud_resource_tags = {}
  }
}

*/
