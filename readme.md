<!--
This file is part of QuickLab, which creates simple, monitored labs.
https://github.com/jeff-d/quicklab

SPDX-FileCopyrightText: © 2025 Jeffrey M. Deininger <9385180+jeff-d@users.noreply.github.com>
SPDX-License-Identifier: AGPL-3.0-or-later
-->

| Monitoring | [ ![ Datadog ](https://github.com/jeff-d/qlpoc/actions/workflows/build-datadog.yaml/badge.svg?event=push) ](https://github.com/jeff-d/qlpoc/blob/main/.github/workflows/build-datadog.yaml) |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

# Terraform Implementation Details

Why the configuration is shaped the way it is, file by file. There is a section per resource-creating file; the ones marked _inline_ still carry their reasoning as comments in the code and have not been moved yet.

This module is consumed by [jeff-d/qlpoc](https://github.com/jeff-d/qlpoc) as `module.datadog`, resolved from `main`, so a change reaches a lab only once it is pushed and picked up by `terraform init -upgrade`. The rules these notes answer to — single-shot apply, single-shot destroy, controller lifetimes — are in that repo's `AGENTS.md`, and how the two repos are wired to each other (the reference-carrier variables, the namespace teardown barrier) is in its readme under "Terraform Implementation Details / Datadog". What follows is this module's own internals.

Where an ordering or a value is not recoverable from reading a resource in isolation, the code carries a one-line marker pointing back here, in the form `# see readme.md "Terraform Implementation Details / <file>"`. Treat those markers as load-bearing.

## agent.tf

_Inline._

## aws-integration.tf

_Inline._

## cloudprem.tf

_Inline._

## cloudtrail.tf

_Inline._

## costmanagement.tf

### The export's query names every column

CUR 2.0 is a fixed format and nothing about it is being inferred. The query exists because AWS's `CreateExport` API requires a `QueryStatement`: per the [Data Exports query docs](https://docs.aws.amazon.com/cur/latest/userguide/dataexports-data-query.html), the console builds the SQL from the options you tick, while SDK and CLI callers write their own. Terraform is an SDK caller, so `local.cur_columns` reproduces the `SELECT` the console would have generated. The documented grammar names columns explicitly; `SELECT *` is not part of it.

Which columns to name comes from Datadog's [CCM AWS setup guide](https://docs.datadoghq.com/cloud_cost_management/setup/aws/), which does not enumerate columns either. It specifies content and delivery settings, and then states that all string-valued CUR columns are added as tags on cost metrics. So the rule is: set the table properties Datadog names, then select the complete schema those properties produce. Omitting a column only costs a tag. Regenerate the list with:

```bash
aws bcm-data-exports get-table --region us-east-1 \
  --table-name COST_AND_USAGE_REPORT \
  --table-properties '{"TIME_GRANULARITY":"HOURLY","INCLUDE_RESOURCES":"TRUE","INCLUDE_SPLIT_COST_ALLOCATION_DATA":"TRUE","INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY":"FALSE"}' \
  | jq -r '.Schema[].Name'
```

That returns 127 columns. The baseline schema with both content options off is 115, and turning on the two Datadog requires adds exactly `line_item_resource_id` plus the eleven `split_line_item_*` columns.

### Content options are Datadog's, the rest are AWS's, and they are immutable

`INCLUDE_RESOURCES` and `INCLUDE_SPLIT_COST_ALLOCATION_DATA` are the two content options Datadog's docs require, and `TIME_GRANULARITY = "HOURLY"` is the granularity they ask for. Split cost allocation also needs AWS Split Cost Allocation opted in under Cost Explorer preferences. `INCLUDE_IAM_PRINCIPAL_DATA` (optional in the docs, scoped to user-level Bedrock allocation) and `INCLUDE_CAPACITY_RESERVATION_DATA` (not mentioned at all) are left off; enabling both would add four more columns. `INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"` and `BILLING_VIEW_ARN` are AWS-side requirements rather than Datadog ones — the Terraform resource requires every table configuration value once any is set, and the CUR table additionally requires a billing view.

On the delivery side, `PARQUET` satisfies the docs' "GZIP or Parquet" and `CREATE_NEW_REPORT` matches "create new report version"; `OVERWRITE_REPORT` is cheaper if the bucket's 7-day lifecycle is not enough, at the cost of departing from the documented setting. `SYNCHRONOUS` is the only value AWS accepts for `refresh_cadence`, and is what "refresh automatically" means in API terms.

Get the content options right on the first apply. AWS does not allow table configurations to change after an export is created, and the provider marks `table_configurations`, `name`, `format`, `compression`, and `output_type` as requiring replacement. `query_statement` is updatable in place, so the column list can be revised later without replacing the export.

### Report access is granted for the export, not a CUR definition

`aws_iam_policy.datadog_cur_access` scopes `s3:GetObject` to `<bucket>/<local.cur_prefix>/<export name>/*` and adds `bcm-data-exports:ListExports` and `GetExport`, which are what the validator's `EXPORT_LIST_PERMISSION_MISSING` and `EXPORT_GET_PERMISSION_MISSING` codes check. Those two actions already arrive with `DatadogAWSIntegrationPolicy-1` from the permissions data source, so restating them here is about keeping this policy self-contained. `cur:DescribeReportDefinitions` stays even though the legacy CUR is gone — Datadog's own CCM CloudFormation template still includes it.

Bucket ACLs are a leftover: `aws_s3_bucket_ownership_controls.cur` keeps them enabled because the legacy CUR wrote with a `bucket-owner-full-control` ACL, but Data Exports delivers through its service principal and the bucket policy instead.

### The CCM config is gated on Datadog's own validator

Creating the CCM config immediately after the AWS integration races Datadog's Cloud Cost service, which has to see the new integration before it can assume the role and read the bucket. Under the legacy `datadog_aws_cur_config` resource that race had no read-only signal to wait on; it surfaced as a `BUCKET_ACCESS` failure about a second after the integration was created.

CUR 2.0 makes it observable. `POST /api/v2/integration/aws/validate_ccm_config` runs the same role-assumption and S3 checks and returns a structured `issues` list, so `terraform_data.datadog_ccm_config_ready` waits on a real condition instead of a sleep. It reads the `workflow-automation` API and application keys from Secrets Manager rather than taking them as module inputs, which keeps them out of state and matches how `cloudprem.tf` does the same thing. `datadog_integration_aws_account_ccm_config` depends on this gate, so the gate must never list that resource in its own `depends_on`.

`datadog_integration_aws_account_ccm_config` is a subresource of the AWS account config (`/api/v2/integration/aws/accounts/{id}/ccm_config`), so its dependency on the integration is an attribute reference rather than a `depends_on`.

### Validator issue codes are classified, not treated alike

Only some of the validator's codes can clear on their own, so `local.ccm_validation_ignored_issue_codes` and `local.ccm_validation_terminal_issue_codes` split the [published enum](https://github.com/DataDog/datadog-api-client-go/blob/master/api/datadogV2/model_aws_ccm_config_validation_issue_code.go) three ways:

| Class | Codes | Behavior |
|---|---|---|
| Terminal | `BUCKET_NAME_INVALID_GOVCLOUD`, `S3_BUCKET_REGION_MISMATCH`, `TIME_GRANULARITY_INVALID`, `FILE_FORMAT_INVALID`, `INCLUDE_RESOURCES_DISABLED`, `REFRESH_CADENCE_INVALID`, `OVERWRITE_MODE_INVALID`, `QUERY_STATEMENT_INVALID` | Fail immediately. These describe the export's own settings, so polling would just burn five minutes on a config error. |
| Ignored | `S3_GET_PERMISSION_MISSING` | Reported as a warning, then treated as a pass. Datadog probes for objects AWS may not deliver for up to 24 hours; the code says nothing about whether the integration has propagated. |
| Everything else | `CREDENTIAL_ERROR`, `S3_LIST_PERMISSION_MISSING`, `S3_BUCKET_NOT_ACCESSIBLE`, `EXPORT_NOT_FOUND`, `EXPORT_LIST_PERMISSION_MISSING`, `EXPORT_GET_PERMISSION_MISSING`, `EXPORT_STATUS_UNHEALTHY` | Retried for up to five minutes. This is what propagation delay looks like. |

Non-200 responses are retried on the same budget, except 401 and 403: a 404 here is the race and must be retried, but bad keys never recover. If the validator endpoint changes — it is still marked unstable in Datadog's API clients — the fallback is a fixed sleep, since this is only a gate.

## forwarder.tf

_Inline._

## kubernetes.tf

_Inline._

## main.tf

_Inline._
