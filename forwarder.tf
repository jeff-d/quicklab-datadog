module "datadog_forwarder" {
  source  = "DataDog/log-lambda-forwarder-datadog/aws"
  version = "~> 1.0"
  tags    = local.cloud_resource_tags # tag the supported AWS resources created by this module


  # Parameters reference: https://docs.datadoghq.com/logs/guide/forwarder/?tab=manual#parameters
  dd_api_key = var.datadog_api_key
  #! dd_api_key_secret_arn is interpolated (not referenced by resource id) because it must be != null at plan time to prevent the module from creating it's own secret
  #! dd_api_key_secret_arn = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.prefix}-${var.uid}-datadog-collection-api-key"
  dd_site = var.datadog_site

  # Lambda function
  function_name         = "${var.prefix}-${var.uid}-datadog-forwarder"
  reserved_concurrency  = 10
  log_retention_in_days = 1
  dd_max_workers        = null   # (string)
  dd_enhanced_metrics   = false  # adds additional custom metrics used to inspect the Forwarder function's performance
  dd_log_level          = "WARN" # log level for the Forwarder function. DEBUG|INFO|WARN|ERROR|CRITICAL (default: "WARN")

  # Log forwarding
  dd_use_compression   = true
  dd_compression_level = 9
  # dd_multiline_log_regex_pattern = "\d{2}\/\d{2}\/\d{4}" # use to detect multi-line logs from S3 beginning with pattern “11/10/2014”
  # dd_tags = join(",", [for k, v in local.datadog_tags : "${k}:${v}" if v != null]) # a comma-separated string of key:value pairs to tag the telemetry forwarded to Datadog.

  # Log scrubbing
  redact_email = false
  redact_ip    = false

  # Log filtering
  exclude_at_match = null # (string) regex

  # Advanced

  # tag 'enrichment' is done by the Datadog backend by default for S3 and Cloudwatch
  # tag colisions can occur if AWS tags on the bucket or log group exist for Datadog reserved tag keys (e.g. service, env, host, team)  
  # dd_enrich_s3_tags = false 
  # dd_enrich_cloudwatch_tags    = false

  # tag 'fetching' is done by the Forwarder during transmission (increasaes Forwarder overhead)
  # dd_fetch_lambda_tags         = false

  dd_step_functions_trace_enabled = true
  dd_fetch_step_functions_tags    = true

  dd_store_failed_events          = true
  dd_forwarder_bucket_name        = "${var.prefix}-${var.uid}-datadog-collection-${data.aws_region.current.region}" #? how to treat as a prefix to name-collision provision failures
  dd_schedule_retry_failed_events = true
  # dd_schedule_retry_interval = 6 # (integer) default: 6
  # tags_cache_ttl_seconds = 60 # (integer) default: 300
}
