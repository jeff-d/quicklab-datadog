module "datadog_forwarder" {
  source  = "DataDog/log-lambda-forwarder-datadog/aws"
  version = "~> 1.0"
  tags    = local.cloud_resource_tags # tag the supported AWS resources created by this module


  # Parameters reference: https://docs.datadoghq.com/logs/guide/forwarder/?tab=manual#parameters
  #! dd_api_key_secret_arn = module.datadog_secrets["api-key-forwarder"].secret_arn 
  #! can't be referenced (via module.datadog_secrets["api-key-forwarder"].secret_arn) so datadog_forwarder module knows whether to create a "aws_secretsmanager_secret" "dd_api_key_secret" at plan time
  #! can't be interpolated from (by constructing an arn) because secret arns add a unique string on the end of secret name that can't be known in advance
  #! dd_api_key_secret_arn = 
  dd_api_key = var.datadog_api_key #! let the module make it's own secret for the forwarder to solve the above BYO secret problem
  dd_site    = var.datadog_site

  # Lambda function
  function_name         = "${var.prefix}-${var.uid}-datadog-forwarder"
  layer_version         = "93" # default: "latest" #! 94 is broken due to python 3.14 upgrade: https://github.com/DataDog/terraform-aws-log-lambda-forwarder-datadog/pull/22
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
  dd_enrich_cloudwatch_tags = true

  # tag 'fetching' is done by the Forwarder during transmission (increasaes Forwarder overhead)
  # dd_fetch_lambda_tags         = false

  dd_step_functions_trace_enabled = true
  dd_fetch_step_functions_tags    = true

  dd_store_failed_events          = true
  dd_forwarder_bucket_name        = "${var.prefix}-${var.uid}-${local.module}-forwarder-${data.aws_region.current.region}" #? how to treat as a prefix to avoid name-collision provision failures
  dd_schedule_retry_failed_events = true
  # dd_schedule_retry_interval = 6 # (integer) default: 6
  # tags_cache_ttl_seconds = 60 # (integer) default: 300
}
