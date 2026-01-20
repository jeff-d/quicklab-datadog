# install datadog agent via configuration management
resource "aws_ssm_association" "server_install" {
  for_each         = var.create_server ? toset(var.server_os) : []
  name             = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:865078226113:document/datadog-agent-installation-${each.value}"
  association_name = "datadog-agent-installation-${each.value}_${var.prefix}-${var.uid}"
  parameters = merge(
    {
      action = "InstallOrUpgrade"                                        #! no default action specified for Windows document
      apikey = try(datadog_api_key.this["agent-installation"].key, null) #! secret leaks in: SSM State Manager -> Association ID -> Parameters
      site   = var.datadog_site
      # hostname = null                             
      tags = join(",", [for k, v in local.datadog_tags : "${k}:${v}" if v != null]) # a comma-separated string of key:value pairs
    }
  )

  targets {
    key    = "tag:os"
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

# enable Workflows to work with the Datadog API
#! no Datadog Action Connection resource exists in datadog terraform provider 3.83.0
resource "datadog_action_connection" "http" {
  # test the action connection with at https://app.datadoghq.com/actions/connections 
  # with a GET to Test URL: "{{base_url}}/api/v1/validate"

  name = "${var.prefix}-${var.uid}-actions-${local.module}-http"

  http {
    base_url = "https://api.${var.datadog_site}"

    token_auth {

      token {
        type  = "SECRET"
        name  = "apikey"
        value = datadog_api_key.this["workflow-automation"].key
      }

      header {
        name  = "DD-API-KEY"
        value = "{{ apikey }}"
      }

      token {
        type  = "SECRET"
        name  = "appkey" # token names must match regexp: "^[A-Za-z][A-Za-z\\\\d]*$\"
        value = datadog_application_key.this["workflow-automation"].key
      }

      header {
        name  = "DD-APPLICATION-KEY"
        value = "{{ appkey }}"
      }

      header {
        name  = "Accept"
        value = "application/json"
      }

    }
  }

  # lifecycle { ignore_changes = [http] } #! suppresses supurious plan drift but prevents detection of actual token change
}

# Workflow creates Fleet Automation configuration deployment
resource "datadog_workflow_automation" "agent_config" {
  count       = var.create_server ? 1 : 0
  name        = "Manage Datadog Agent Configuration"
  description = "Updates the configuration of scoped Datadog Agents on a schedule via a Fleet Automation configuration deployment."
  published   = true
  tags        = [for k, v in local.datadog_tags : "${k}:${v}" if v != null] # a list of key:value pairs

  spec_json = jsonencode(
    {

      connectionEnvs = [{
        connections = [{
          connectionId = datadog_action_connection.http.id
          label        = datadog_action_connection.http.name
        }]
        env = "default"
      }]

      handle = "manage-datadog-agent-config"

      inputSchema = {
        parameters = [
          {
            name        = "this_quicklab_id"
            label       = "Quicklab ID"
            type        = "STRING"
            description = "the id of this quicklab"
            # defaultValue = ""
          },
          {
            name         = "datadog_agent_hostname"
            label        = "Datadog agent hostname"
            type         = "STRING"
            description  = "the hostname identified by the Datadog agent"
            defaultValue = "default-value"
          }
        ]
      }

      steps = [
        {
          actionId        = "com.datadoghq.http.request"
          connectionLabel = datadog_action_connection.http.name
          name            = "Create_Fleet_Automation_Deployment" #! "name Enable Logs via Fleet Automation is invalid. Name cannot be empty, must be unique, and can only contain alphanumeric characters and underscores. It cannot start with a number."
          parameters = [
            {
              name = "body"
              value = {
                data = {
                  attributes = {
                    config_operations = [{
                      file_op   = "merge-patch"
                      file_path = "/datadog.yaml"
                      patch = {
                        process_config = {
                          process_collection = {
                            enabled = true
                          }
                        }
                        logs_enabled = true
                        logs_config = {
                          file_wildcard_selection_mode = "by_modification_time"
                        }
                      }
                    }]
                    filter_query = "quicklab-id:{{ Trigger.this_quicklab_id }} AND hostname:{{ Trigger.datadog_agent_hostname }}" # compound filter_query can result in a failed workflow execution: "quicklab-id:${var.uid} AND -enabled_products:logs"
                  }
                  type = "deployment"
                }
              }
            },
            {
              name = "requestHeaders"
              value = [
                {
                  key   = "Content-Type"
                  value = ["application/json"]
                }
              ]
            },
            {
              name  = "url"
              value = "https://api.datadoghq.com/api/unstable/fleet/deployments/configure"
            },
            {
              name  = "verb"
              value = "POST"
            }
          ]
          display = {
            bounds = {
              x = 0
              y = 192
            }
          }
          # outboundEdges = []
        }
      ]

      triggers = [
        {
          monitorTrigger = {
            rateLimit = {
              count    = 100
              interval = "86400s" # the number of seconds ending with an s. For example, 1 day is 86400s
            }
          }
          startStepNames = ["Create_Fleet_Automation_Deployment"]
        }
      ]

    }
  )
}

# Audit Trail Monitor to trigger Workflow
resource "datadog_monitor" "new_agent" {
  count = var.create_server ? 1 : 0

  name             = "New Datadog Agent Installed"
  type             = "audit alert"
  priority         = "5" # (string) Integer from 1 (high) to 5 (low)
  new_host_delay   = 0
  new_group_delay  = 0
  evaluation_delay = 0    #? necessary for audit alerts? 
  include_tags     = true # default: true
  # groupby_simple_monitor = false
  # .rollup("count").by(\"@metadata.host_metadata.hostname\").last("1m") > 0 
  # .rollup("count").last("1m") > 0 
  query = <<EOT
            audits("@evt.name:\"Datadog Agent\" @action:created status:info").rollup("count").by("@metadata.host_metadata.hostname").last("1m") > 0 
          EOT

  # wrapping message in monitor variables prevents additional workflow trigger on Monitor recovery
  message = "{{#is_alert}} Let's fire @workflow-manage-datadog-agent-config(this_quicklab_id=\"${var.uid}\",datadog_agent_hostname=\"{{[@metadata.host_metadata.hostname].name}}\") {{/is_alert}}"

  monitor_thresholds { critical = 0 }

  tags = [for k, v in local.datadog_tags : "${k}:${v}" if v != null] # a list of key:value pairs
}

#! UNUSED (agent config patch)
/*

#! process_config seems to produce error:
#! 400 Bad Request: {"errors":[{"title":"Failed to create configuration. 
#! Supported integrations are: apache, docker, gunicorn, kafka, logs, pgbouncer, redisdb, snmp, tomcat, win32_event_log. 
#! Please try again or contact support if the issue persists"}]}

patch = {
  process_config = {
    process_collection = {
      enabled = true
    }
    run_in_core_agent = {
      enabled = true
    }
  }
  logs_enabled = true
  logs_config = {
    file_wildcard_selection_mode = "by_modification_time"
  }
}

*/


#! UNUSED (intended to set hostname during agent installation)
/*

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

*/

#! UNUSED (part of workflow spec)
/*


    inputSchema = {
      parameters = [
        {
          defaultValue = "quicklab-id:${var.uid}",
          name         = "filterQuery",
          type         = "STRING"
        }
      ]
    }

    
    outputSchema = {
      parameters = [
        {
          name  = "output",
          type  = "ARRAY_OBJECT",
          value = "outputValue"
        }
      ]
    }

triggers = [
  {
    scheduleTrigger = {
      rruleExpression = "FREQ=MINUTELY;INTERVAL=30" # fleet automation deployment run duration is 4m for 1 agent and 8m for 2 agents
    }
    startStepNames = ["Create_Fleet_Automation_Deployment"]
  }
]

*/

#! UNUSED (part of monitor definition)
/*
priority = "5" 
include_tags = true # default: true
tags = [for k, v in local.datadog_tags : "${k}:${v}" if v != null] # a list of key:value pairs

# draft_status = "draft" # draft|published (default: published)

# query:
# https://docs.datadoghq.com/api/latest/monitors/#audit-alert-query
audits('@evt.name:\"Datadog Agent\" @action:created).rollup('count').by('@metadata.host_metadata.hostname').last('5m') > 0
"@action:created AND @evt.name:'Datadog Agent' AND -status:error"

Audit Alert Query
Example: audits(query).rollup(rollup_method[, measure]).last(time_window) operator #

query The search query - following the Log search syntax.
rollup_method The stats roll-up method - supports count, avg and cardinality.
measure For avg and cardinality rollup_method - specify the measure or the facet name you want to use.
time_window #m (between 1 and 2880), #h (between 1 and 48).
operator <, <=, >, >=, ==, or !=.
# an integer or decimal number used to set the threshold.

query    = "audits(@evt.name:\"Datadog Agent\" @action:created).rollup(count).last(5m) > 0"

query = <<EOT
audits("@evt.name:\"Datadog Agent\" @action:created").rollup("count").last("5m") < 0
EOT

query    = <<EOT
              audits("@evt.name:\"Datadog Agent\" @action:created").rollup("count").last("5m") > 0
              EOT


*/

#! UNUSED (uninstall datadog agent)
/*

resource "aws_ssm_association" "server_uninstall" {
  for_each         = var.create_server ? toset(var.server_os) : []
  name             = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:865078226113:document/datadog-agent-installation-${each.value}"
  association_name = "datadog-agent-uninstall-${each.value}_${var.prefix}-${var.uid}"
  parameters = merge(
    {
      action = "Uninstall"                                               #! no default action specified for Windows document
      apikey = try(datadog_api_key.this["agent-installation"].key, null) #! secret leaks in: SSM State Manager -> Association ID -> Parameters
      site   = var.datadog_site
      # hostname = null                             
      tags = join(",", [for k, v in local.datadog_tags : "${k}:${v}" if v != null]) # a comma-separated string of key:value pairs
    }
  )

  lifecycle {
    replace_triggered_by = [datadog_api_key.this["agent-installation"].key, terraform_data.datadog_tags]
  }

}

*/
