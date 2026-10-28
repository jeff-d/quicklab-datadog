# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# One mock covers both http data sources in the graph, because mock_data keys on the
# data source type rather than its address.
#
# The shape below is what the forwarder module requires: it calls jsondecode() on the
# response and reads .latest and .mappings, with no try() around it, so a generated
# random string fails the plan.
mock_data "http" {
  defaults = {
    status_code   = 200
    response_body = "{\"latest\":{\"layer_version\":\"93\",\"forwarder_version\":\"5.2.0\"},\"mappings\":{\"93\":\"5.2.0\"},\"entries\":{\"datadog-operator\":[{\"version\":\"2.32.0-dev.1\"},{\"version\":\"2.31.0\"}]}}"
  }
}
