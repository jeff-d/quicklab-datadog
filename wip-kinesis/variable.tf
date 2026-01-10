variable datadog_http_endpoint_url {
  type = string
  default = "https://aws-kinesis-http-intake.logs.datadoghq.com/v1/input"
}

variable datadog_api_key {
  type = string
}

variable failed_log_delivery_prefix {
  type = string
}

