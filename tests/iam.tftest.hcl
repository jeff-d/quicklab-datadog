# This file is part of QuickLab, which creates simple, observable labs.
# https://github.com/jeff-d/quicklab
#
# SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# The permission-chunking arithmetic in aws-integration.tf, which splits the permission
# list Datadog publishes across as many managed policies as it takes to stay under AWS's
# 6144-byte limit.
#
# Worth isolating for two reasons. It fails only at apply, against a hard AWS limit, so
# nothing catches an off-by-one until a real deploy. And its input grows whenever Datadog
# adds a permission, so the module can cross the threshold with no change to this
# repository at all.

mock_provider "aws" { source = "./tests/mocks/aws" }
mock_provider "datadog" { source = "./tests/mocks/datadog" }
mock_provider "helm" {}
mock_provider "http" { source = "./tests/mocks/http" }

variables {
  prefix       = "quicklab"
  uid          = "ab12"
  datadog_site = "datadoghq.com"
}

# Synthetic input rather than a snapshot of the live list, so the expected chunk count is
# arithmetic that stays true rather than a fixture that goes stale. Each of the 208
# entries is 54 characters, and the module budgets 3 more per entry for JSON quoting and
# the separating comma, giving 11856 bytes against a 5900-byte target: three chunks of
# 103, 104, and 1 permissions. Three matters more than two, because only a three-chunk
# split exercises a middle chunk, which is bounded on both sides and is where an
# off-by-one would hide.
#
# The list is spelled out because override_data values must be literals; Terraform
# rejects function calls there, so it cannot be generated with a for expression.
run "large_permission_sets_are_chunked_under_the_aws_limit" {
  command = plan

  override_data {
    target = data.datadog_integration_aws_iam_permissions.all
    values = {
      iam_permissions = [
        "synthetic000:DescribeResourceAttributesForChunkingTest", "synthetic001:DescribeResourceAttributesForChunkingTest", "synthetic002:DescribeResourceAttributesForChunkingTest", "synthetic003:DescribeResourceAttributesForChunkingTest",
        "synthetic004:DescribeResourceAttributesForChunkingTest", "synthetic005:DescribeResourceAttributesForChunkingTest", "synthetic006:DescribeResourceAttributesForChunkingTest", "synthetic007:DescribeResourceAttributesForChunkingTest",
        "synthetic008:DescribeResourceAttributesForChunkingTest", "synthetic009:DescribeResourceAttributesForChunkingTest", "synthetic010:DescribeResourceAttributesForChunkingTest", "synthetic011:DescribeResourceAttributesForChunkingTest",
        "synthetic012:DescribeResourceAttributesForChunkingTest", "synthetic013:DescribeResourceAttributesForChunkingTest", "synthetic014:DescribeResourceAttributesForChunkingTest", "synthetic015:DescribeResourceAttributesForChunkingTest",
        "synthetic016:DescribeResourceAttributesForChunkingTest", "synthetic017:DescribeResourceAttributesForChunkingTest", "synthetic018:DescribeResourceAttributesForChunkingTest", "synthetic019:DescribeResourceAttributesForChunkingTest",
        "synthetic020:DescribeResourceAttributesForChunkingTest", "synthetic021:DescribeResourceAttributesForChunkingTest", "synthetic022:DescribeResourceAttributesForChunkingTest", "synthetic023:DescribeResourceAttributesForChunkingTest",
        "synthetic024:DescribeResourceAttributesForChunkingTest", "synthetic025:DescribeResourceAttributesForChunkingTest", "synthetic026:DescribeResourceAttributesForChunkingTest", "synthetic027:DescribeResourceAttributesForChunkingTest",
        "synthetic028:DescribeResourceAttributesForChunkingTest", "synthetic029:DescribeResourceAttributesForChunkingTest", "synthetic030:DescribeResourceAttributesForChunkingTest", "synthetic031:DescribeResourceAttributesForChunkingTest",
        "synthetic032:DescribeResourceAttributesForChunkingTest", "synthetic033:DescribeResourceAttributesForChunkingTest", "synthetic034:DescribeResourceAttributesForChunkingTest", "synthetic035:DescribeResourceAttributesForChunkingTest",
        "synthetic036:DescribeResourceAttributesForChunkingTest", "synthetic037:DescribeResourceAttributesForChunkingTest", "synthetic038:DescribeResourceAttributesForChunkingTest", "synthetic039:DescribeResourceAttributesForChunkingTest",
        "synthetic040:DescribeResourceAttributesForChunkingTest", "synthetic041:DescribeResourceAttributesForChunkingTest", "synthetic042:DescribeResourceAttributesForChunkingTest", "synthetic043:DescribeResourceAttributesForChunkingTest",
        "synthetic044:DescribeResourceAttributesForChunkingTest", "synthetic045:DescribeResourceAttributesForChunkingTest", "synthetic046:DescribeResourceAttributesForChunkingTest", "synthetic047:DescribeResourceAttributesForChunkingTest",
        "synthetic048:DescribeResourceAttributesForChunkingTest", "synthetic049:DescribeResourceAttributesForChunkingTest", "synthetic050:DescribeResourceAttributesForChunkingTest", "synthetic051:DescribeResourceAttributesForChunkingTest",
        "synthetic052:DescribeResourceAttributesForChunkingTest", "synthetic053:DescribeResourceAttributesForChunkingTest", "synthetic054:DescribeResourceAttributesForChunkingTest", "synthetic055:DescribeResourceAttributesForChunkingTest",
        "synthetic056:DescribeResourceAttributesForChunkingTest", "synthetic057:DescribeResourceAttributesForChunkingTest", "synthetic058:DescribeResourceAttributesForChunkingTest", "synthetic059:DescribeResourceAttributesForChunkingTest",
        "synthetic060:DescribeResourceAttributesForChunkingTest", "synthetic061:DescribeResourceAttributesForChunkingTest", "synthetic062:DescribeResourceAttributesForChunkingTest", "synthetic063:DescribeResourceAttributesForChunkingTest",
        "synthetic064:DescribeResourceAttributesForChunkingTest", "synthetic065:DescribeResourceAttributesForChunkingTest", "synthetic066:DescribeResourceAttributesForChunkingTest", "synthetic067:DescribeResourceAttributesForChunkingTest",
        "synthetic068:DescribeResourceAttributesForChunkingTest", "synthetic069:DescribeResourceAttributesForChunkingTest", "synthetic070:DescribeResourceAttributesForChunkingTest", "synthetic071:DescribeResourceAttributesForChunkingTest",
        "synthetic072:DescribeResourceAttributesForChunkingTest", "synthetic073:DescribeResourceAttributesForChunkingTest", "synthetic074:DescribeResourceAttributesForChunkingTest", "synthetic075:DescribeResourceAttributesForChunkingTest",
        "synthetic076:DescribeResourceAttributesForChunkingTest", "synthetic077:DescribeResourceAttributesForChunkingTest", "synthetic078:DescribeResourceAttributesForChunkingTest", "synthetic079:DescribeResourceAttributesForChunkingTest",
        "synthetic080:DescribeResourceAttributesForChunkingTest", "synthetic081:DescribeResourceAttributesForChunkingTest", "synthetic082:DescribeResourceAttributesForChunkingTest", "synthetic083:DescribeResourceAttributesForChunkingTest",
        "synthetic084:DescribeResourceAttributesForChunkingTest", "synthetic085:DescribeResourceAttributesForChunkingTest", "synthetic086:DescribeResourceAttributesForChunkingTest", "synthetic087:DescribeResourceAttributesForChunkingTest",
        "synthetic088:DescribeResourceAttributesForChunkingTest", "synthetic089:DescribeResourceAttributesForChunkingTest", "synthetic090:DescribeResourceAttributesForChunkingTest", "synthetic091:DescribeResourceAttributesForChunkingTest",
        "synthetic092:DescribeResourceAttributesForChunkingTest", "synthetic093:DescribeResourceAttributesForChunkingTest", "synthetic094:DescribeResourceAttributesForChunkingTest", "synthetic095:DescribeResourceAttributesForChunkingTest",
        "synthetic096:DescribeResourceAttributesForChunkingTest", "synthetic097:DescribeResourceAttributesForChunkingTest", "synthetic098:DescribeResourceAttributesForChunkingTest", "synthetic099:DescribeResourceAttributesForChunkingTest",
        "synthetic100:DescribeResourceAttributesForChunkingTest", "synthetic101:DescribeResourceAttributesForChunkingTest", "synthetic102:DescribeResourceAttributesForChunkingTest", "synthetic103:DescribeResourceAttributesForChunkingTest",
        "synthetic104:DescribeResourceAttributesForChunkingTest", "synthetic105:DescribeResourceAttributesForChunkingTest", "synthetic106:DescribeResourceAttributesForChunkingTest", "synthetic107:DescribeResourceAttributesForChunkingTest",
        "synthetic108:DescribeResourceAttributesForChunkingTest", "synthetic109:DescribeResourceAttributesForChunkingTest", "synthetic110:DescribeResourceAttributesForChunkingTest", "synthetic111:DescribeResourceAttributesForChunkingTest",
        "synthetic112:DescribeResourceAttributesForChunkingTest", "synthetic113:DescribeResourceAttributesForChunkingTest", "synthetic114:DescribeResourceAttributesForChunkingTest", "synthetic115:DescribeResourceAttributesForChunkingTest",
        "synthetic116:DescribeResourceAttributesForChunkingTest", "synthetic117:DescribeResourceAttributesForChunkingTest", "synthetic118:DescribeResourceAttributesForChunkingTest", "synthetic119:DescribeResourceAttributesForChunkingTest",
        "synthetic120:DescribeResourceAttributesForChunkingTest", "synthetic121:DescribeResourceAttributesForChunkingTest", "synthetic122:DescribeResourceAttributesForChunkingTest", "synthetic123:DescribeResourceAttributesForChunkingTest",
        "synthetic124:DescribeResourceAttributesForChunkingTest", "synthetic125:DescribeResourceAttributesForChunkingTest", "synthetic126:DescribeResourceAttributesForChunkingTest", "synthetic127:DescribeResourceAttributesForChunkingTest",
        "synthetic128:DescribeResourceAttributesForChunkingTest", "synthetic129:DescribeResourceAttributesForChunkingTest", "synthetic130:DescribeResourceAttributesForChunkingTest", "synthetic131:DescribeResourceAttributesForChunkingTest",
        "synthetic132:DescribeResourceAttributesForChunkingTest", "synthetic133:DescribeResourceAttributesForChunkingTest", "synthetic134:DescribeResourceAttributesForChunkingTest", "synthetic135:DescribeResourceAttributesForChunkingTest",
        "synthetic136:DescribeResourceAttributesForChunkingTest", "synthetic137:DescribeResourceAttributesForChunkingTest", "synthetic138:DescribeResourceAttributesForChunkingTest", "synthetic139:DescribeResourceAttributesForChunkingTest",
        "synthetic140:DescribeResourceAttributesForChunkingTest", "synthetic141:DescribeResourceAttributesForChunkingTest", "synthetic142:DescribeResourceAttributesForChunkingTest", "synthetic143:DescribeResourceAttributesForChunkingTest",
        "synthetic144:DescribeResourceAttributesForChunkingTest", "synthetic145:DescribeResourceAttributesForChunkingTest", "synthetic146:DescribeResourceAttributesForChunkingTest", "synthetic147:DescribeResourceAttributesForChunkingTest",
        "synthetic148:DescribeResourceAttributesForChunkingTest", "synthetic149:DescribeResourceAttributesForChunkingTest", "synthetic150:DescribeResourceAttributesForChunkingTest", "synthetic151:DescribeResourceAttributesForChunkingTest",
        "synthetic152:DescribeResourceAttributesForChunkingTest", "synthetic153:DescribeResourceAttributesForChunkingTest", "synthetic154:DescribeResourceAttributesForChunkingTest", "synthetic155:DescribeResourceAttributesForChunkingTest",
        "synthetic156:DescribeResourceAttributesForChunkingTest", "synthetic157:DescribeResourceAttributesForChunkingTest", "synthetic158:DescribeResourceAttributesForChunkingTest", "synthetic159:DescribeResourceAttributesForChunkingTest",
        "synthetic160:DescribeResourceAttributesForChunkingTest", "synthetic161:DescribeResourceAttributesForChunkingTest", "synthetic162:DescribeResourceAttributesForChunkingTest", "synthetic163:DescribeResourceAttributesForChunkingTest",
        "synthetic164:DescribeResourceAttributesForChunkingTest", "synthetic165:DescribeResourceAttributesForChunkingTest", "synthetic166:DescribeResourceAttributesForChunkingTest", "synthetic167:DescribeResourceAttributesForChunkingTest",
        "synthetic168:DescribeResourceAttributesForChunkingTest", "synthetic169:DescribeResourceAttributesForChunkingTest", "synthetic170:DescribeResourceAttributesForChunkingTest", "synthetic171:DescribeResourceAttributesForChunkingTest",
        "synthetic172:DescribeResourceAttributesForChunkingTest", "synthetic173:DescribeResourceAttributesForChunkingTest", "synthetic174:DescribeResourceAttributesForChunkingTest", "synthetic175:DescribeResourceAttributesForChunkingTest",
        "synthetic176:DescribeResourceAttributesForChunkingTest", "synthetic177:DescribeResourceAttributesForChunkingTest", "synthetic178:DescribeResourceAttributesForChunkingTest", "synthetic179:DescribeResourceAttributesForChunkingTest",
        "synthetic180:DescribeResourceAttributesForChunkingTest", "synthetic181:DescribeResourceAttributesForChunkingTest", "synthetic182:DescribeResourceAttributesForChunkingTest", "synthetic183:DescribeResourceAttributesForChunkingTest",
        "synthetic184:DescribeResourceAttributesForChunkingTest", "synthetic185:DescribeResourceAttributesForChunkingTest", "synthetic186:DescribeResourceAttributesForChunkingTest", "synthetic187:DescribeResourceAttributesForChunkingTest",
        "synthetic188:DescribeResourceAttributesForChunkingTest", "synthetic189:DescribeResourceAttributesForChunkingTest", "synthetic190:DescribeResourceAttributesForChunkingTest", "synthetic191:DescribeResourceAttributesForChunkingTest",
        "synthetic192:DescribeResourceAttributesForChunkingTest", "synthetic193:DescribeResourceAttributesForChunkingTest", "synthetic194:DescribeResourceAttributesForChunkingTest", "synthetic195:DescribeResourceAttributesForChunkingTest",
        "synthetic196:DescribeResourceAttributesForChunkingTest", "synthetic197:DescribeResourceAttributesForChunkingTest", "synthetic198:DescribeResourceAttributesForChunkingTest", "synthetic199:DescribeResourceAttributesForChunkingTest",
        "synthetic200:DescribeResourceAttributesForChunkingTest", "synthetic201:DescribeResourceAttributesForChunkingTest", "synthetic202:DescribeResourceAttributesForChunkingTest", "synthetic203:DescribeResourceAttributesForChunkingTest",
        "synthetic204:DescribeResourceAttributesForChunkingTest", "synthetic205:DescribeResourceAttributesForChunkingTest", "synthetic206:DescribeResourceAttributesForChunkingTest", "synthetic207:DescribeResourceAttributesForChunkingTest",
      ]
    }
  }

  assert {
    condition     = length(local.permission_chunks) == 3
    error_message = "Expected 11856 bytes of permissions to split into 3 chunks, got ${length(local.permission_chunks)}."
  }

  # The limit the whole mechanism exists to respect.
  assert {
    condition = alltrue([
      for chunk in local.permission_chunks :
      sum([for perm in chunk : length(perm) + 3]) <= 6144
    ])
    error_message = "A permission chunk exceeds the 6144-byte AWS managed policy limit."
  }

  # Chunking has to partition the input, not sample it. A dropped permission is invisible
  # until some Datadog product quietly fails to collect.
  assert {
    condition     = length(flatten(local.permission_chunks)) == length(local.iam_permissions)
    error_message = "Chunking dropped or duplicated permissions: ${length(flatten(local.permission_chunks))} of ${length(local.iam_permissions)}."
  }

  assert {
    condition     = tolist(sort(flatten(local.permission_chunks))) == tolist(sort(local.iam_permissions))
    error_message = "The chunks do not contain exactly the permissions Datadog returned."
  }

  # One managed policy per chunk, each attached to the cross-account role.
  assert {
    condition     = length(aws_iam_policy.datadog_aws_integration) == length(local.permission_chunks)
    error_message = "Every chunk needs its own managed policy."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.datadog_aws_integration) == length(local.permission_chunks)
    error_message = "Every chunk's policy needs to be attached to the integration role."
  }

  # Names carry a 1-based chunk suffix, so they stay distinct as the list grows.
  assert {
    condition     = length(distinct([for p in aws_iam_policy.datadog_aws_integration : p.name])) == length(aws_iam_policy.datadog_aws_integration)
    error_message = "Chunked policy names must be unique."
  }

  assert {
    condition     = aws_iam_policy.datadog_aws_integration[0].name == "quicklab-ab12-DatadogAWSIntegrationPolicy-1"
    error_message = "Unexpected chunked policy name: ${aws_iam_policy.datadog_aws_integration[0].name}"
  }
}

# The small end of the range: a list that fits in one policy should not be split.
run "small_permission_sets_produce_one_policy" {
  command = plan

  assert {
    condition     = length(local.permission_chunks) == 1
    error_message = "A permission list well under the limit should not be chunked."
  }

  assert {
    condition     = length(aws_iam_policy.datadog_aws_integration) == 1
    error_message = "A permission list well under the limit should produce exactly one managed policy."
  }
}
