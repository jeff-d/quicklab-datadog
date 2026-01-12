# install datadog agent via configuration management
resource "aws_ssm_association" "server" {
  for_each         = toset(var.server_os)
  name             = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:865078226113:document/datadog-agent-installation-${each.value}"
  association_name = "Datadog-agent-installation-${each.value}"
  parameters = merge(
    {
      action   = "InstallOrUpgrade"                                        #! no default action specified for Windows document
      apikey   = try(datadog_api_key.this["agent-installation"].key, null) #! secret leaks in: SSM State Manager -> Association ID -> Parameters
      site     = var.datadog_site
      hostname = try(local.linux_server_private_dns, null)                              #! will be null if only creating windows servers
      tags     = join(",", [for k, v in local.datadog_tags : "${k}:${v}" if v != null]) # a comma-separated string of key:value pairs
    }
  )

  targets {
    key    = "tag:ServerOS"
    values = [each.value]
  }

  targets {
    key    = "tag:quicklab-id"
    values = [var.uid]
  }

  lifecycle {
    replace_triggered_by = [datadog_api_key.this["agent-installation"].key, terraform_data.datadog_tags]
  }
}

# store datadog tags values in a resource to use with lifecycle replacement logic for the aws_ssm_association
resource "terraform_data" "datadog_tags" {
  input = var.datadog_tags
}

locals {
  # get the one linux instance's private dns name 
  linux_server_private_dns = try(data.aws_instance.linux_server[0].private_dns, null)


  # get the instance id of the first one (should only be one)
  linux_server_instance_id = (
    contains(var.server_os, "linux") && length(data.aws_instances.linux_server[0].ids) > 0
    ? sort(data.aws_instances.linux_server[0].ids)[0]
    : null
  )
}

# get the full instance details for the one linux instance
data "aws_instance" "linux_server" {
  count = contains(var.server_os, "linux") && local.linux_server_instance_id != null ? 1 : 0

  instance_id = local.linux_server_instance_id

  depends_on = [data.aws_instances.linux_server]
}

# get the linux server instances
data "aws_instances" "linux_server" {
  count = contains(var.server_os, "linux") ? 1 : 0

  instance_state_names = ["running"]

  filter {
    name   = "tag:ServerOS"
    values = ["linux"]
  }

  filter {
    name   = "tag:quicklab-id"
    values = [var.uid]
  }
}
