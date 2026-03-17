# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


locals {
  datadog_operator_helm_chart_version = "2.19.1" # corresponds to App version 1.24.0
  datadog_operator_helm_release_name  = "datadog-operator"
  datadog_operator_namespace          = "datadog"

  datadog_operator_values = {
    # https://artifacthub.io/packages/helm/datadog/datadog-operator?modal=values
    apiKey      = try(datadog_api_key.this["kubernetes-operator"].key, null)
    appKey      = try(datadog_application_key.this["kubernetes-operator"].key, null)
    clusterName = var.cluster_name
    site        = var.datadog_site

    introspection       = { enabled = true }
    remoteConfiguration = { enabled = true }

    tolerations = [{
      key      = "karpenter.sh/controller"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  }
}

resource "helm_release" "datadog_operator" {
  count = length(var.cluster_name) > 0 ? 1 : 0

  name       = local.datadog_operator_helm_release_name
  repository = "https://helm.datadoghq.com/" # https://artifacthub.io/packages/helm/datadog/"
  chart      = "datadog-operator"
  version    = local.datadog_operator_helm_chart_version

  atomic           = true
  namespace        = local.datadog_operator_namespace
  create_namespace = true
  upgrade_install  = true
  timeout          = 300

  values = [yamlencode(local.datadog_operator_values)] # object keys merge, arrays replace 
}

resource "local_file" "datadog_agent_manifest" {
  count = length(var.cluster_name) > 0 ? 1 : 0

  content = templatefile(
    "${path.module}/templates/DatadogAgent-deployment.tftpl",
    {
      DATADOG_OPERATOR_NAMESPACE = local.datadog_operator_namespace
      DATADOG_SITE               = var.datadog_site
      DATADOG_API_KEY            = try(datadog_api_key.this["kubernetes-operator"].key, null)
      DATADOG_APP_KEY            = try(datadog_api_key.this["kubernetes-operator"].key, null)
    }
  )
  filename        = "${path.module}/templates/DatadogAgent-deployment.yaml"
  file_permission = "0600"
}

resource "terraform_data" "datadog_agent_manifest" {
  count = length(var.cluster_name) > 0 ? 1 : 0
  depends_on = [
    helm_release.datadog_operator,
    local_file.datadog_agent_manifest
  ]
  triggers_replace = [
    var.cluster_name,
    local_file.datadog_agent_manifest[0].content_sha256
  ]

  provisioner "local-exec" {
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl apply -f "$MANIFEST_PATH"
    EOT
    environment = {
      CLUSTER_NAME  = var.cluster_name
      MANIFEST_PATH = local_file.datadog_agent_manifest[0].filename
    }
  }
}
