# This file is part of QuickLab, which creates simple, observable labs.
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
variable "vpc_id" { type = string }
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
variable "create_server" {
  type        = bool
  description = "A flag flag for resource creation. Set to \"true\" to enable."
  default     = false
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
variable "server_otelcol" {
  type        = bool
  description = "Bootstrap QuickLab servers with the OpenTelemetry Collector (agent)."
  default     = false
}
variable "cluster_name" {
  type        = string
  default     = null
  description = "Name of the EKS cluster to integrate with Datadog. Set to null (or omit) when no QuickLab cluster is provisioned."
}
variable "create_byoc_k8s_deployments" {
  type        = bool
  description = "A flag for 'bring your own cloud' kubernetes deployment creation (Datadog Observability Pipelines and Datadog CloudPrem). Set to \"true\" to enable."
  default     = false
}
variable "cloudprem_retention" {
  type        = number
  default     = 7
  description = "Number of days to retain logs in a Datadog CloudPrem index. Applies both to the CloudPrem Cluster's retention settings and the AWS S3 Bucket's lifecycle configuration."
}
variable "enable_cloud_security" {
  type        = bool
  description = "Enable Datadog Cloud Security products. Set to \"true\" to enable."
  default     = false
}
