# This file is part of QuickLab, which creates simple, monitored labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

data "datadog_ip_ranges" "org" {}

resource "datadog_organization_settings" "output" {
}

output "agent_endpoints" {
  value = data.datadog_ip_ranges.org.agents_ipv4
}

output "org_name" {
  value = datadog_organization_settings.output.name
}
output "org_id" {
  value = datadog_organization_settings.output.id
}
output "org_public_id" {
  value = datadog_organization_settings.output.public_id
}
