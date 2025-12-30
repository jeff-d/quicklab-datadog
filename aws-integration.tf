# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later


## Datadog AWS Integration
# https://docs.datadoghq.com/integrations/amazon-web-services/
# https://docs.datadoghq.com/integrations/guide/aws-terraform-setup/
# https://app.datadoghq.com/screen/integration/7/aws-overview

data "datadog_integration_aws_available_namespaces" "all" {}

data "datadog_integration_aws_available_logs_services" "all" {}

data "datadog_integration_aws_iam_permissions" "all" {}

data "aws_iam_policy_document" "datadog_aws_integration_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::464622532012:root"] # Datadog AWS Account that assumes your cross-account Role
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values = [
        "${datadog_integration_aws_account.datadog_integration.auth_config.aws_auth_config_role.external_id}"
      ]
    }
  }
}

locals {
  # the iam_permissions list returned by datadog_integration_aws_iam_permissions 
  # is a superset of the iam_permissions lists in datadog_integration_aws_iam_permissions_standard 
  # and datadog_integration_aws_iam_permissions_resource_collection
  iam_permissions = data.datadog_integration_aws_iam_permissions.all.iam_permissions

  max_policy_size   = 6144
  target_chunk_size = 5900

  permission_sizes = [
    for perm in local.iam_permissions :
    length(perm) + 3
  ]
  cumulative_sizes = [
    for i in range(length(local.permission_sizes)) :
    sum(slice(local.permission_sizes, 0, i + 1))
  ]

  chunk_assignments = [
    for cumulative_size in local.cumulative_sizes :
    floor(cumulative_size / local.target_chunk_size)
  ]
  chunk_numbers = distinct(local.chunk_assignments)
  permission_chunks = [
    for chunk_num in local.chunk_numbers : [
      for i, perm in local.iam_permissions :
      perm if local.chunk_assignments[i] == chunk_num
    ]
  ]
}

data "aws_iam_policy_document" "datadog_aws_integration" {
  count = length(local.permission_chunks)

  statement {
    actions   = local.permission_chunks[count.index]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "datadog_aws_integration" {
  count = length(local.permission_chunks)

  name   = "${var.prefix}-${var.uid}-DatadogAWSIntegrationPolicy-${count.index + 1}"
  policy = data.aws_iam_policy_document.datadog_aws_integration[count.index].json

  tags = local.cloud_resource_tags
}

resource "aws_iam_role" "datadog_aws_integration" {
  name               = var.integration_role_name != "DatadogIntegrationRole" ? var.integration_role_name : "${var.prefix}-${var.uid}-DatadogIntegrationRole"
  description        = "Role for Datadog AWS Integration"
  assume_role_policy = data.aws_iam_policy_document.datadog_aws_integration_assume_role.json

  tags = local.cloud_resource_tags
}

resource "aws_iam_role_policy_attachment" "datadog_aws_integration" {
  count = length(local.permission_chunks)

  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = aws_iam_policy.datadog_aws_integration[count.index].arn
}

resource "aws_iam_role_policy_attachment" "datadog_aws_integration_securityaudit" {
  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_iam_role_policy_attachment" "datadog_aws_integration_readonlyaccess" {
  # contains additional permissions required for Extended Resource Collection on additional Datadog Products
  # https://docs.datadoghq.com/integrations/amazon-web-services/#resource-types-and-permissions

  role       = aws_iam_role.datadog_aws_integration.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

locals {
  taggable_namespaces = ["AWS/ApplicationELB", "AWS/ELB", "AWS/EC2", "AWS/Lambda", "AWS/AmazonMQ", "AWS/Kafka", "AWS/NetworkELB", "AWS/RDS", "AWS/SQS", "AWS/States"]
  include_metric_namespaces = [
    # AI
    "AWS/Bedrock/Guardrails", "AWS/ML", "AWS/SageMaker", "AWS/SageMaker/TrainingJobs",

    # serverless
    "AWS/ApiGateway",

    # data stores
    "AWS/RDS", "AWS/S3",

    # data streaming
    "AWS/ElasticMapReduce", "AWS/Firehose", "AWS/Kafka", "AWS/Kinesis", "AWS/KinesisAnalytics",
    "AWS/KinesisVideo",

    # infrastructure
    "AWS/ApplicationELB", "AWS/ELB", "AWS/NetworkELB", "AWS/Route53", "AWS/StorageGateway",
    "AWS/TransitGateway", "AWS/VPC", "AWS/WAF", "AWS/WAFV2",

    # compute
    "AWS/EBS", "AWS/EC2", "AWS/EC2Spot", "AWS/ECR", "AWS/ECS",
    "ECS/ContainerInsights", "EKS/ContainerInsights", "AWS/IoT", "AWS/IoTAnalytics", "AWS/WorkSpaces",

    # events
    "AWS/Events", "AWS/SES", "AWS/SNS", "AWS/SQS",

    # VDI
    "AWS/WorkSpaces", "AWS/WorkSpacesWeb", "AWS/WorkSpacesThinClient", "AWS/WorkSpaces/Usage", "AWS/WorkSpaces/Pool",
    "AWS/WorkSpacesProtocol", "AWS/WorkSpaces/Status", "AWS/WorkSpaces/Session", "AWS/WorkSpacesWeb/Session", "AWS/WorkSpacesWeb/Portal",

    # common
    "AWS/CertificateManager", "AWS/ACMPrivateCA",

    # auditing
    "AWS/CloudTrail", "AWS/IAM", "AWS/KMS",
  ]
  autosubscribe_log_sources = ["cloudtrail", "vpc"]
}

resource "datadog_integration_aws_account" "datadog_integration" {
  account_tags   = [for k, v in local.datadog_tags : "${k}:${v}"] # list(string) Tags to apply to all metrics in the account. 
  aws_account_id = var.aws_account_id
  aws_partition  = "aws"

  aws_regions {
    include_only = ["${var.aws_region}"] # alternative to the empty-block behavior 'include_all  = true'
  }

  auth_config {
    aws_auth_config_role {
      role_name = var.integration_role_name != "DatadogIntegrationRole" ? var.integration_role_name : "${var.prefix}-${var.uid}-DatadogIntegrationRole" #* using aws_iam_role.datadog_aws_integration.name gives a tf cycle error
    }
  }

  resources_config {
    cloud_security_posture_management_collection = false
    extended_collection                          = true # required for cloud_security_posture_management_collection
  }

  metrics_config {
    # automute_enabled          = true # default: true (ref: https://docs.datadoghq.com/integrations/amazon-ec2/?tab=awssystemsmanagerssm#ec2-automuting)
    # collect_cloudwatch_alarms = true  # default: false
    # collect_custom_metrics    = true  # default: false
    # enabled                   = true  # default: true

    namespace_filters {
      # pick an approach: include_only or exclude_only 
      # omitting both (an empty block) defaults to: exclude_only = ["AWS/SQS", "AWS/ElasticMapReduce", "AWS/Usage"] 
      # to reduce your AWS CloudWatch costs from GetMetricData API calls

      # include_only allowed values in data.datadog_integration_aws_available_namespaces

      include_only = [
        for ns in local.include_metric_namespaces :
        ns if contains(data.datadog_integration_aws_available_namespaces.all.aws_namespaces, ns)
      ]
    }

    dynamic "tag_filters" {
      for_each = local.taggable_namespaces
      iterator = namespace
      content {
        namespace = namespace.value
        tags      = ["quicklab.io:lab-id:${var.uid}"]
      }
    }
  }

  logs_config {

    lambda_forwarder {
      # lambdas = ["arn:aws:lambda:us-east-1:123456789012:function:my-lambda"] # Supports multiple forwarder ARNs. Only 1 Lambda function is required per AWS region for log collection.
      sources = [for src in local.autosubscribe_log_sources : src if contains(data.datadog_integration_aws_available_logs_services.all.aws_logs_services, src)]

      # sources = ["s3"] # allowed values in data.datadog_integration_aws_available_logs_services
      /*
      log_source_config {
        tag_filters {
          source = "s3"
          tags   = ["env:prod", "team:backend"]
        }
      */
    }

  }

  traces_config {
    xray_services {
      # include_all = true (overrides xray_services empty block behavior for include_only)
      # include_only = [] # default: []
    }
  }
}


## Reference

/*
# collectable metric namespaces
all_metric_namespaces = [
    "AWS/AmplifyHosting", "AWS/ApiGateway", "AWS/AppFlow", "AWS/MGN", "AWS/AppRunner", 
    "AWS/AppStream", "AWS/AppSync", "AWS/Athena", "AWS/RDS", "AWS/Backup",
    "AWS/Bedrock/Guardrails", "AWS/Billing", "AWS/Braket/ByDevice", "AWS/CertificateManager", "AWS/ACMPrivateCA", 
    "AWS/Chatbot", "AWS/ChimeVoiceConnector", "AWS/ChimeSDK", "AWS/ClientVPN", "AWS/CloudFront", 
    "AWS/CloudHSM", "AWS/CloudSearch", "AWS/CloudTrail", "CWAgent or a custom namespace", "ApplicationSignals",
    "AWS/CloudWatch/MetricStreams", "AWS/RUM", "CloudWatchSynthetics", "AWS/Logs", "AWS/CodeBuild", 
    "AWS/CodeGuruReviewer", "AWSCodePipeline", "AWS/Kendra", "AWS/Cognito", "AWS/Connect", 
    "AWS/DDoSProtection", "AWS/DataSync", "AWS/DirectConnect", "AWS/DX", "AWS/DocDB", 
    "AWS/DynamoDB", "AWS/DAX", "AWS/EBS", "AWS/EC2", "AWS/EC2Spot", 
    "AWS/ELB", "AWS/ApplicationELB", "AWS/ElasticBeanstalk", "AWS/ECS", "AWS/EKS", 
    "AWS/EFS", "AWS/ElastiCache", "AWS/MediaConvert", "AWS/MediaPackage", "AWS/MediaStore", 
    "AWS/MediaTailor", "AWS/ES", "AWS/ElasticMapReduce", "AWS/Firehose", "AWS/FMS", 
    "AWS/FSx", "AWS/GameLift", "AWS/GlobalAccelerator", "AWS/Glue", "AWS/InspectorV2", 
    "AWS/IoT", "AWS/IoTAnalytics", "AWS/IVS", "AWS/IVSRealTime", "AWS/Kafka", 
    "AWS/Kinesis", "AWS/KinesisAnalytics", "AWS/KinesisVideo", "AWS/Lambda", "AWS/Lex", 
    "AWS/LicenseManager", "AWS/Logs/Containers", "AWS/Logs/Insights", "AWS/Logs/EMF", "Container Insights", 
    "AWS/MemoryDB", "AWS/ML", "AWS/Neptune", "AWS/NetworkELB", "AWS/NATGateway", 
    "AWS/OpsWorks", "AWS/Personalize", "AWS/Polly", "AWS/PrivateLinkEndpoints", "AWS/RabbitMQ", 
    "AWS/Redshift", "AWS/RefactorSpaces", "AWS/Route53", "AWS/S3", "AWS/SageMaker", 
    "AWS/SageMaker/TrainingJobs", "AWS/SDKMetrics", "AWS/SES", "AWS/SNS", "AWS/SQS", 
    "AWS/States", "AWS/StorageGateway", "AWS/SWF", "AWS/Transfer", "AWS/TransitGateway", 
    "AWS/TrustedAdvisor", "AWS/Usage", "AWS/VPN", "AWS/WAF", "AWS/WAFV2", 
    "AWS/WorkSpaces", "AWS/WorkSpacesWeb", "AWS/XRay", "ECS/ContainerInsights", "EKS/ContainerInsights", 
    "Kubernetes/ContainerInsights", "AWS/CodeGuruProfiler", "AWS/CodeGuruSecurity", "AWS/Comprehend", "AWS/Config", 
    "AWS/CostExplorer", "AWS/DatabaseMigrationService", "AWS/DEVOPS_GURU", "AWS/DirectoryService", "AWS/ECR", 
    "AWS/ElasticInference", "AWS/ELASTICFILESYSTEM", "AWS/ElementalMediaLive", "AWS/Events", "AWS/GroundStation", 
    "AWS/Health", "AWS/IAM", "AWS/KMS", "AWS/LookoutMetrics", "AWS/MQ", 
    "AWS/NimbleStudio", "AWS/Pricing", "AWS/RDS/PerformanceInsights", "AWS/Robomaker", "AWS/ServiceCatalog", 
    "AWS/SecurityHub", "AWS/Shield", "AWS/Signer", "AWS/Snowball", "AWS/SSM", 
    "AWS/StorageLens", "AWS/Textract", "AWS/Transcribe", "AWS/Translate", "AWS/TrustedAdvisor/Check", 
    "AWS/VPC", "AWS/WebRTC", "AWS/Wisdom", "AWS/WorkMail", "AWS/WorkSpacesThinClient",
    "AWS/WorkSpaces/Usage", "AWS/WorkSpaces/Pool", "AWS/WorkSpacesProtocol", "AWS/WorkSpaces/Status", "AWS/WorkSpaces/Session", 
    "AWS/WorkSpacesWeb/Session", "AWS/WorkSpacesWeb/Portal"
  ]

  all_aws_logs_services = [
  "apigw-access-logs", "apigw-execution-logs", "appsync", "batch", "cloudfront", 
  "cloudtrail", "codebuild", "dms", "docdb", "ecs", 
  "eks", "eks-container-insights", "elb", "elbv2", "lambda", 
  "lambda-edge", "mwaa", "network-firewall", "pcs", "rds", 
  "redshift", "redshift-serverless", "route53", "route53-resolver", "s3", 
  "ssm", "states", "verified-access", "vpc", "vpn", 
  "waf"
  ]
  */
