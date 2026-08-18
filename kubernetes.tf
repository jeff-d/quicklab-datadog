# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


locals {
  datadog_operator_helm_chart_version = "2.19.1" # corresponds to App version 1.24.0
  datadog_operator_helm_release_name  = "datadog-operator"
  datadog_operator_namespace          = "datadog"

  # Not "datadog-secret": that name is already taken in this namespace by the secret the
  # operator generates from the DatadogAgent CR's own credentials, so reusing it collides.
  datadog_agent_keys_secret = "datadog-agent-keys"

  datadog_operator_values = {
    # https://artifacthub.io/packages/helm/datadog/datadog-operator?modal=values
    apiKey      = try(datadog_api_key.this["kubernetes-operator"].key, null)
    appKey      = try(datadog_application_key.this["kubernetes-operator"].key, null)
    clusterName = var.cluster_name
    site        = var.datadog_site

    introspection       = { enabled = true }
    remoteConfiguration = { enabled = true }
    datadogSLO          = { enabled = false } # default: false

    datadogCRDs = {
      crds = {
        # datadogCRDs.crds.datadogSLOs -- Set to true to deploy the DatadogSLO CRD
        datadogSLOs : false # default: false
      }
    }

    tolerations = [{
      key      = "karpenter.sh/controller"
      operator = "Exists"
      effect   = "NoSchedule"
    }]

  }

  datadog_agent_deployment = {
    features = {
      logCollection                = true
      logCollectionContainerAll    = true
      liveProcessCollection        = true
      liveContainerCollection      = true
      processDiscovery             = true
      oomKill                      = true
      tcpQueueLength               = true
      ebpfCheck                    = false
      apm                          = true
      asmThreats                   = true
      asmSca                       = true
      asmIast                      = true
      cspm                         = var.enable_cloud_security
      cws                          = var.enable_cloud_security
      npm                          = true
      usm                          = true
      dogstatsdUnixDomainSocket    = true
      otlpGrpc                     = false
      remoteConfiguration          = true
      sbom                         = true
      sbomContainerImage           = true
      sbomHost                     = true
      serviceDiscovery             = true
      serviceDiscoveryNetworkStats = true
      gpu                          = false
      collectKubernetesEvents      = true
      orchestratorExplorer         = true
      kubeStateMetricsCore         = true
      admissionController          = true
      externalMetricsServer        = true
      clusterChecks                = true
      prometheusScrape             = false
    }
  }
}

resource "helm_release" "datadog_operator" {
  count      = local.quicklab_cluster_enabled ? 1 : 0
  depends_on = [var.kubeconfig_ready]

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

# Hold the Agent's credentials in a Kubernetes secret rather than as literals in the
# DatadogAgent CR, so the generated DatadogAgent-deployment.yaml on disk carries no keys.
# triggers_replace hashes the keys (rather than omitting them) so a rotation actually
# reaches the cluster; hashing keeps plaintext out of plan output.
resource "terraform_data" "datadog_agent_secrets" {
  count      = local.quicklab_cluster_enabled ? 1 : 0
  depends_on = [helm_release.datadog_operator] # creates the namespace (create_namespace = true)

  triggers_replace = [
    var.cluster_name,
    local.datadog_operator_namespace,
    local.datadog_agent_keys_secret,
    sha256(try(datadog_api_key.this["kubernetes-operator"].key, "")),
    sha256(try(datadog_application_key.this["kubernetes-operator"].key, "")),
  ]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl create secret generic $SECRET_NAME --namespace $NAMESPACE --from-literal api-key=$DD_API_KEY --from-literal app-key=$DD_APP_KEY --dry-run=client -o yaml | kubectl apply -f -
    EOT
    environment = {
      CLUSTER_NAME = var.cluster_name
      NAMESPACE    = local.datadog_operator_namespace
      SECRET_NAME  = local.datadog_agent_keys_secret
      DD_API_KEY   = try(datadog_api_key.this["kubernetes-operator"].key, null)
      DD_APP_KEY   = try(datadog_application_key.this["kubernetes-operator"].key, null)
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl delete secret $SECRET_NAME --namespace $NAMESPACE --ignore-not-found
    EOT
    environment = {
      CLUSTER_NAME = self.triggers_replace[0]
      NAMESPACE    = self.triggers_replace[1]
      SECRET_NAME  = self.triggers_replace[2]
    }
  }
}

resource "local_file" "datadog_agent_manifest" {
  count = local.quicklab_cluster_enabled ? 1 : 0

  content = templatefile(
    "${path.module}/templates/DatadogAgent-deployment.tftpl",
    {
      DATADOG_OPERATOR_NAMESPACE = local.datadog_operator_namespace
      DATADOG_SITE               = var.datadog_site
      DATADOG_KEYS_SECRET        = local.datadog_agent_keys_secret
      DATADOG_AGENT_DEPLOYMENT   = local.datadog_agent_deployment
      # Scheme is required: without http:// the Agent defaults to HTTPS/TLS, CloudPrem
      # indexers speak plain HTTP on 7280, and the Agent falls back to TLS-TCP which
      # never ingest. Docs: https://docs.datadoghq.com/cloudprem/ingest/agent/
      CLOUDPREM_INDEXER_URL = var.create_byoc_k8s_deployments ? "http://cloudprem-indexer.${local.cloudprem.namespace}.svc.cluster.local:7280" : ""
    }
  )
  filename        = "${path.module}/templates/DatadogAgent-deployment.yaml"
  file_permission = "0600"
}

resource "terraform_data" "datadog_agent_manifest" {
  count = local.quicklab_cluster_enabled ? 1 : 0
  # Deliberately not ordered after helm_release.cloudprem: the CR references CloudPrem only as
  # a DNS string, never as a Kubernetes object, so the edge buys no correctness and instead
  # couples failures. helm_release.cloudprem sets atomic = true, so a failed CloudPrem install
  # errors the apply and the CR would never be applied at all, taking out metrics, APM, live
  # processes, and orchestrator explorer along with logs. The Agent self-heals instead: the
  # logs agent retries a missing destination indefinitely with backpressure, and file-tailer
  # offsets are not committed until a send succeeds.
  depends_on = [
    helm_release.datadog_operator,
    local_file.datadog_agent_manifest,
    terraform_data.datadog_agent_secrets,
  ]
  triggers_replace = [
    var.cluster_name,
    local.datadog_operator_namespace,
    local_file.datadog_agent_manifest[0].content_sha256
  ]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl apply -f "$MANIFEST_PATH"
    EOT
    environment = {
      CLUSTER_NAME  = var.cluster_name
      MANIFEST_PATH = local_file.datadog_agent_manifest[0].filename
    }
  }

  # Delete the CR (and wait for it) while the operator is still around to process its
  # finalizer — depends_on above already sequences this before helm_release.datadog_operator
  # is uninstalled.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl delete datadogagent datadog --namespace $NAMESPACE --ignore-not-found --wait=true --timeout=120s
    EOT
    environment = {
      CLUSTER_NAME = self.triggers_replace[0]
      NAMESPACE    = self.triggers_replace[1]
    }
  }
}
