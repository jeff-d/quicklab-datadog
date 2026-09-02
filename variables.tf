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
variable "vpc_id" {
  type        = string
  default     = null
  description = "ID of the VPC hosting CloudPrem. Only read when cluster_enabled and create_byoc_k8s_deployments are both true; omit otherwise."
}
variable "datadog_site" {
  type        = string
  description = "Datadog site parameter in domain form (e.g. datadoghq.com), not the region code (e.g. US1). Reference: https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site"

  validation {
    condition = contains([
      "datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com",
      "datadoghq.eu", "uk1.datadoghq.com",
      "ddog-gov.com", "us2.ddog-gov.com",
      "ap1.datadoghq.com", "ap2.datadoghq.com",
    ], var.datadog_site)
    error_message = "Must be a Datadog site parameter in domain form (e.g. datadoghq.com), not a region code (e.g. US1). Reference: https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site"
  }
}
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
variable "autosubscribe_log_sources" {
  type        = list(string)
  description = "A list of log-ready AWS services to autosubscribe to the Datadog Forwarder lambda function."
  default     = []
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
    condition     = alltrue([for os in var.server_os : contains(["linux", "windows"], os)])
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
variable "cluster_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether the caller's Cluster component is enabled. Gates this module's cluster-facing
    resources.

    Deliberately separate from var.cluster_name rather than derived from it. The name is
    built from a managed resource attribute, so on a greenfield build it is unknown until
    apply, and count/for_each cannot accept an unknown. This flag comes straight from the
    caller's own create_cluster input, so it is always known at plan time. Do not
    "simplify" the two into one input.
  EOT
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

  validation {
    condition     = var.cloudprem_retention > 0
    error_message = "Must be a positive number of days: an S3 lifecycle expiration of 0 deletes objects immediately."
  }
}
variable "cloudprem_chart_version" {
  type        = string
  default     = null
  description = "CloudPrem Helm chart version to deploy. Defaults to latest from helm.datadoghq.com."
}
variable "enable_cloud_security" {
  type        = bool
  description = "Enable Datadog Cloud Security products. Set to \"true\" to enable."
  default     = false
}
variable "kubeconfig_ready" {
  type        = any
  default     = null
  description = <<-EOT
    Opaque reference-carrier used only to order this module's Kubernetes-touching resources
    (helm_release.datadog_operator, helm_release.cloudprem, terraform_data.cloudprem_secrets)
    after the QuickLab Cluster component's kubeconfig file is written. The value itself is
    never read by this module; only the resource reference the caller assigns to it matters
    for Terraform's dependency graph. Deliberately not depended on at the whole-module level,
    so AWS-only resources in this module aren't serialized behind cluster creation.
  EOT
}
variable "lbc_ready" {
  type        = any
  default     = null
  description = <<-EOT
    Opaque reference-carrier used only to order terraform_data.cloudprem_secrets after the
    QuickLab Cluster component's aws-load-balancer-controller release. The value itself is never
    read; only the reference matters for the dependency graph.

    This edge exists for destroy, not create. The CloudPrem chart creates an Ingress that the
    controller reconciles into an ALB and holds the ingress.k8s.aws/resources finalizer on.
    Terraform destroys dependents first, so making the namespace's owner depend on the controller
    keeps the controller running until the namespace is gone. Without it the two are siblings
    (both merely downstream of the kubeconfig), the controller can be uninstalled first, and the
    Ingress then blocks namespace deletion indefinitely while its ALB leaks. See also the
    Controller lifetimes ADR in ../qlpoc/AGENTS.md.
  EOT
}
variable "karpenter_ready" {
  type        = any
  default     = null
  description = <<-EOT
    Opaque reference-carrier used only to order terraform_data.cloudprem_secrets after the
    QuickLab Cluster component's Karpenter NodePool/EC2NodeClass. The value itself is never
    read; only the reference matters for the dependency graph. Null when the cluster is
    disabled or when cluster_autoscaler is not "karpenter".

    Like lbc_ready this edge is about destroy, but it protects capacity rather than credentials.
    CloudPrem's pods run on Karpenter-provisioned nodes, and deleting the NodePool starts
    draining them. Without this edge the NodePool delete and the namespace delete are siblings,
    so the nodes can be torn out from under pods that are still running: the NodeClaim cannot
    drain, the sweep in ../qlpoc/cluster.tf force-terminates the instance, and the orphaned pods
    stay Terminating until Karpenter reconciles the dead node -- which routinely overruns the
    namespace delete's timeout. Ordering the NodePool after the namespace means the nodes are
    already empty when the NodePool goes, so the drain is immediate.

    On create this correctly makes CloudPrem wait for the NodePool to exist, so its pods have
    somewhere to schedule instead of sitting Pending against the release's atomic timeout.
  EOT
}
