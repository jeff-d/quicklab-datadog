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
#
# cloudprem.tf's data.http.datadog_helm_index also receives this body. That is harmless:
# yamldecode parses JSON, the lookup for .entries["cloudprem"] misses, and the existing
# try() falls back to its pinned chart version. Tests that care about chart resolution
# override this data source with a YAML fixture of their own.
mock_data "http" {
  defaults = {
    status_code   = 200
    response_body = "{\"latest\":{\"layer_version\":\"93\",\"forwarder_version\":\"5.2.0\"},\"mappings\":{\"93\":\"5.2.0\"}}"
  }
}
