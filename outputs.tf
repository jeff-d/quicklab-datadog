# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

data "datadog_ip_ranges" "org" {}

resource "datadog_organization_settings" "this" {
  # no settings configured
  # this resource is used only to read settings and populate terraform outputs

  lifecycle {
    ignore_changes = [name]
  }
}

output "agent_endpoints" {
  value = data.datadog_ip_ranges.org.agents_ipv4
}

output "org_name" {
  value = datadog_organization_settings.this.name
}

output "org_id" {
  value = datadog_organization_settings.this.id
}

output "org_public_id" {
  value = datadog_organization_settings.this.public_id
}

output "collection_bucket_name" {
  description = "S3 Bucket where failed deliveries will be saved"
  value       = module.datadog_forwarder.forwarder_bucket_name
}
