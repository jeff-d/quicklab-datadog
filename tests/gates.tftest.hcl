# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The count/for_each gates, one run block per flag combination. Almost all of this
# module's conditional surface hangs off two booleans, and the failure mode when a gate
# is wrong is a plan-time error rather than a bad value, so plan-mode tests catch it.

mock_provider "aws" { source = "./tests/mocks/aws" }
mock_provider "datadog" { source = "./tests/mocks/datadog" }
mock_provider "helm" {}
mock_provider "http" { source = "./tests/mocks/http" }

variables {
  prefix       = "quicklab"
  uid          = "ab12"
  datadog_site = "datadoghq.com"
}

run "cluster_enabled_adds_the_operator" {
  command = plan

  variables {
    cluster_enabled = true
    cluster_name    = "quicklab-ab12-cluster"
  }

  assert {
    condition = keys(datadog_api_key.this) == [
      "agent-installation", "kubernetes-operator", "log-forwarder", "workflow-automation",
    ]
    error_message = "Enabling the cluster should add the kubernetes-operator API key, got: ${join(", ", keys(datadog_api_key.this))}"
  }

  assert {
    condition     = keys(datadog_application_key.this) == ["kubernetes-operator", "workflow-automation"]
    error_message = "Enabling the cluster should add the kubernetes-operator application key, got: ${join(", ", keys(datadog_application_key.this))}"
  }

  assert {
    condition     = length(helm_release.datadog_operator) == 1
    error_message = "Enabling the cluster should deploy the Datadog Operator."
  }

  # The operator alone does not imply CloudPrem; that needs the second flag.
  assert {
    condition     = length(helm_release.cloudprem) == 0
    error_message = "CloudPrem should not deploy without create_byoc_k8s_deployments."
  }
}

run "byoc_with_cluster_adds_cloudprem" {
  command = plan

  variables {
    cluster_enabled             = true
    cluster_name                = "quicklab-ab12-cluster"
    create_byoc_k8s_deployments = true
    vpc_id                      = "vpc-0123456789abcdef0"
  }

  assert {
    condition     = contains(keys(datadog_api_key.this), "cloudprem")
    error_message = "Enabling BYOC should mint a dedicated cloudprem API key."
  }

  assert {
    condition     = length(helm_release.cloudprem) == 1
    error_message = "Enabling BYOC with a cluster should deploy the CloudPrem chart."
  }

  assert {
    condition     = length(aws_s3_bucket.cloudprem) == 1
    error_message = "CloudPrem requires its own S3 bucket for indexed log storage."
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.cloudprem) == 1
    error_message = "CloudPrem's service account needs a Pod Identity association to reach S3."
  }

  # 32 characters is the AWS limit for an ALB name, and this one is assembled from
  # caller-supplied prefix and uid, so the margin is not visible at the call site.
  assert {
    condition     = length("${var.prefix}-${var.uid}-datadog-cloudprem") <= 32
    error_message = "The CloudPrem internal load balancer name exceeds the 32-character ALB limit."
  }
}

# BYOC without a cluster has nowhere to run, and the flags are independent inputs, so
# nothing stops a caller setting it. This pins what actually happens today: the API key
# is still minted, but no CloudPrem infrastructure is. Asserting it makes the behavior a
# decision rather than an accident, and makes any future change to it deliberate.
run "byoc_without_cluster_mints_key_but_builds_nothing" {
  command = plan

  variables {
    cluster_enabled             = false
    create_byoc_k8s_deployments = true
  }

  assert {
    condition     = contains(keys(datadog_api_key.this), "cloudprem")
    error_message = "The cloudprem API key is gated only on create_byoc_k8s_deployments."
  }

  assert {
    condition     = length(helm_release.cloudprem) == 0
    error_message = "CloudPrem must not deploy without a cluster to deploy it into."
  }

  assert {
    condition     = length(aws_s3_bucket.cloudprem) == 0
    error_message = "CloudPrem's bucket must not be created without a cluster."
  }
}

# Regression test for the failure described under "Gate count and for_each on plan-known
# flags" in ../qlpoc/AGENTS.md. On a greenfield build cluster_name comes from a managed
# resource attribute and is unknown until apply, so every gate has to read
# var.cluster_enabled instead.
#
# Terraform test cannot supply a genuinely unknown value, so null stands in for one. The
# proxy is faithful for the property under test -- if anyone re-derives a gate from the
# name, as in `var.cluster_name != null`, the count drops to zero and this fails -- but
# it diverges in one way, which is why CloudPrem is deliberately left off here: a literal
# null trips aws_eks_pod_identity_association's required-attribute check, where a
# genuinely unknown value would plan cleanly.
run "greenfield_cluster_name_unknown_still_gates_on_the_flag" {
  command = plan

  variables {
    cluster_enabled = true
    cluster_name    = null
  }

  assert {
    condition     = length(helm_release.datadog_operator) == 1
    error_message = "Cluster-facing resources must be gated on var.cluster_enabled, not on var.cluster_name being set."
  }

  assert {
    condition     = contains(keys(datadog_api_key.this), "kubernetes-operator")
    error_message = "The operator's API key must be gated on var.cluster_enabled, not on var.cluster_name being set."
  }
}

run "server_enabled_installs_the_agent_once_per_os" {
  command = plan

  variables {
    create_server = true
    server_os     = ["linux", "windows"]
  }

  assert {
    condition     = keys(aws_ssm_association.server_install) == ["linux", "windows"]
    error_message = "Expected one agent-installation association per OS, got: ${join(", ", keys(aws_ssm_association.server_install))}"
  }

  assert {
    condition     = aws_ssm_association.server_install["linux"].association_name == "datadog-agent-installation-linux_quicklab-ab12"
    error_message = "Unexpected association name: ${aws_ssm_association.server_install["linux"].association_name}"
  }
}

# The OpenTelemetry collector replaces the Datadog Agent rather than joining it, so both
# agent-facing associations are suppressed even though create_server is on.
run "server_with_otelcol_skips_agent_installation" {
  command = plan

  variables {
    create_server               = true
    server_os                   = ["linux"]
    server_otelcol              = true
    cluster_enabled             = true
    cluster_name                = "quicklab-ab12-cluster"
    create_byoc_k8s_deployments = true
    vpc_id                      = "vpc-0123456789abcdef0"
  }

  assert {
    condition     = length(aws_ssm_association.server_install) == 0
    error_message = "server_otelcol should suppress Datadog Agent installation."
  }

  assert {
    condition     = length(aws_ssm_association.datadog_agent_cloudprem_logs) == 0
    error_message = "server_otelcol should suppress the CloudPrem log-tailing association too."
  }
}

# Tailing CloudPrem's logs needs a server to run the Agent on and a CloudPrem to tail,
# and CloudPrem in turn needs the cluster. This association reads the ingress ALB data
# source, so its gate has to match that data source's gate exactly; the pair of runs
# below is the regression test for them drifting apart.
run "cloudprem_log_tailing_with_server_cluster_and_byoc" {
  command = plan

  variables {
    create_server               = true
    server_os                   = ["linux"]
    cluster_enabled             = true
    cluster_name                = "quicklab-ab12-cluster"
    create_byoc_k8s_deployments = true
    vpc_id                      = "vpc-0123456789abcdef0"
  }

  assert {
    condition     = length(aws_ssm_association.datadog_agent_cloudprem_logs) == 1
    error_message = "A server plus a cluster plus BYOC should create the CloudPrem log-tailing association."
  }
}

run "cloudprem_log_tailing_without_a_cluster" {
  command = plan

  variables {
    create_server               = true
    server_os                   = ["linux"]
    cluster_enabled             = false
    create_byoc_k8s_deployments = true
  }

  assert {
    condition     = length(aws_ssm_association.datadog_agent_cloudprem_logs) == 0
    error_message = "Without a cluster there is no CloudPrem ingress to tail, and creating the association indexes an empty data source."
  }
}
