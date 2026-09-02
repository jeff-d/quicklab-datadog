# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# These three data sources are filters, not decorations. aws-integration.tf intersects
# local.include_metric_namespaces against aws_namespaces and var.autosubscribe_log_sources
# against aws_logs_services, keeping only what the API confirms. A mock provider left to
# generate its own values returns empty lists, which would silently reduce every filtered
# result to [] and let assertions pass for the wrong reason.

mock_data "datadog_integration_aws_available_namespaces" {
  defaults = {
    # Mirrors local.include_metric_namespaces in aws-integration.tf, so the baseline
    # state is "nothing is dropped". Tests that care about dropping override this.
    aws_namespaces = [
      "AWS/CloudTrail", "AWS/IAM", "AWS/KMS",
      "AWS/CertificateManager", "AWS/ACMPrivateCA",
      "AWS/Bedrock/Guardrails", "AWS/ML", "AWS/SageMaker", "AWS/SageMaker/TrainingJobs",
      "AWS/ApiGateway", "AWS/Lambda",
      "AWS/RDS", "AWS/S3",
      "AWS/ElasticMapReduce", "AWS/Firehose", "AWS/Kafka", "AWS/Kinesis",
      "AWS/KinesisAnalytics", "AWS/KinesisVideo",
      "AWS/ApplicationELB", "AWS/ELB", "AWS/NetworkELB", "AWS/Route53",
      "AWS/StorageGateway", "AWS/TransitGateway", "AWS/VPC", "AWS/WAF", "AWS/WAFV2",
      "AWS/EBS", "AWS/EC2", "AWS/EC2Spot", "AWS/ECR", "AWS/ECS",
      "ECS/ContainerInsights", "EKS/ContainerInsights", "AWS/IoT", "AWS/IoTAnalytics",
      "AWS/Events", "AWS/SES", "AWS/SNS", "AWS/SQS",
      "AWS/WorkSpaces", "AWS/WorkSpacesWeb", "AWS/WorkSpacesThinClient",
      "AWS/WorkSpaces/Usage", "AWS/WorkSpaces/Pool", "AWS/WorkSpacesProtocol",
      "AWS/WorkSpaces/Status", "AWS/WorkSpaces/Session", "AWS/WorkSpacesWeb/Session",
      "AWS/WorkSpacesWeb/Portal",
    ]
  }
}

mock_data "datadog_integration_aws_available_logs_services" {
  defaults = {
    aws_logs_services = [
      "apigw-access-logs", "apigw-execution-logs", "appsync", "batch", "cloudfront",
      "cloudtrail", "codebuild", "dms", "docdb", "ecs",
      "eks", "eks-container-insights", "elb", "elbv2", "lambda",
      "lambda-edge", "mwaa", "network-firewall", "pcs", "rds",
      "redshift", "redshift-serverless", "route53", "route53-resolver", "s3",
      "ssm", "states", "verified-access", "vpc", "vpn",
      "waf",
    ]
  }
}

mock_data "datadog_integration_aws_iam_permissions" {
  defaults = {
    # Small and realistic. The real list is several hundred entries and drives the
    # policy-chunking arithmetic; tests/iam.tftest.hcl overrides this with a synthetic
    # list sized to force multiple chunks.
    iam_permissions = [
      "apigateway:GET",
      "autoscaling:Describe*",
      "cloudtrail:DescribeTrails",
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "ec2:Describe*",
      "s3:GetBucketLogging",
      "s3:GetBucketTagging",
      "tag:GetResources",
    ]
  }
}

mock_data "datadog_ip_ranges" {
  defaults = {
    agents_ipv4 = ["3.233.144.0/20"]
  }
}
