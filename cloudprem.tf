data "aws_vpc" "quicklab" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  id    = var.vpc_id
}

data "http" "datadog_helm_index" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  url   = "https://helm.datadoghq.com/index.yaml"

  retry {
    attempts     = 3
    min_delay_ms = 1000
    max_delay_ms = 5000
  }
}

data "aws_subnets" "private" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

locals {
  cloudprem = {
    namespace         = "dd"
    helm_release      = "cloudprem"
    cluster_id        = "${var.prefix}-${var.uid}-cloudprem-${data.aws_partition.current.partition}-${data.aws_region.current.region}"
    fullname_override = ""
    name_override     = ""
    internal_lb_name  = "${var.prefix}-${var.uid}-${local.module}-cloudprem" # limit 32 characters
  }
  cloudprem_chart_version = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? (
    coalesce(
      var.cloudprem_chart_version,
      try(yamldecode(data.http.datadog_helm_index[0].response_body).entries["cloudprem"][0].version, "0.5.1")
    )
  ) : null
}

resource "local_file" "cloudprem_values" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  content = templatefile(
    "${path.module}/templates/cloudprem-values.tftpl",
    {
      DATADOG_SITE         = var.datadog_site
      INDEX_RETENTION      = var.cloudprem_retention
      AWS_ACCOUNT_ID       = data.aws_caller_identity.current.account_id
      CLUSTER_ID           = local.cloudprem.cluster_id
      FULLNAME_OVERRIDE    = local.cloudprem.fullname_override
      NAME_OVERRIDE        = local.cloudprem.name_override
      SERVICE_ACCOUNT_NAME = "${var.prefix}-${var.uid}-${local.module}-cloudprem"
      S3_BUCKET_ID         = aws_s3_bucket.cloudprem[0].id
      INTERNAL_LB_NAME     = local.cloudprem.internal_lb_name
    }
  )
  filename        = "${path.module}/templates/cloudprem-values.yaml"
  file_permission = "0600"
}

resource "helm_release" "cloudprem" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  # terraform_data.cloudprem_deregister is a create-time no-op; the edge exists so that on
  # destroy Terraform uninstalls this release (the dependent) before running that resource's
  # deregistration provisioner. See the comment on that resource.
  depends_on = [var.kubeconfig_ready, terraform_data.cloudprem_secrets, module.cloudprem_db,
  local_file.cloudprem_values, terraform_data.cloudprem_deregister]

  name       = local.cloudprem.helm_release
  repository = "https://helm.datadoghq.com/" # https://artifacthub.io/packages/helm/datadog/"
  chart      = "cloudprem"
  version    = local.cloudprem_chart_version

  lint             = true
  upgrade_install  = true
  namespace        = local.cloudprem.namespace
  create_namespace = true
  timeout          = 600 #* create time: ~8 minutes
  atomic           = true
  wait_for_jobs    = true

  values = [local_file.cloudprem_values[0].content]
}

resource "terraform_data" "cloudprem_secrets" {
  count      = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  depends_on = [var.kubeconfig_ready]
  # (module.quicklab_cluster and helm_release.karpenter aren't in scope in this module;
  # var.kubeconfig_ready orders this after the Cluster component's kubeconfig file instead.)
  triggers_replace = [var.cluster_name, local.cloudprem.namespace]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic datadog-secret --namespace $NAMESPACE --from-literal api-key=$DD_API_KEY --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic cloudprem-metastore-uri --namespace $NAMESPACE --from-literal QW_METASTORE_URI="postgres://$USERNAME:$PASSWORD@$ADDRESS:$PORT/$DATABASE" --dry-run=client -o yaml | kubectl apply -f -
    EOT
    environment = {
      NAMESPACE    = local.cloudprem.namespace
      CLUSTER_NAME = var.cluster_name
      DD_API_KEY   = try(datadog_api_key.this["cloudprem"].key, null)
      USERNAME     = module.cloudprem_db[0].db_instance_username
      PASSWORD     = urlencode(random_password.cloudprem_db[0].result) # urlencode to prevent issues with special chars in the connection string
      ADDRESS      = module.cloudprem_db[0].db_instance_address
      PORT         = module.cloudprem_db[0].db_instance_port
      DATABASE     = module.cloudprem_db[0].db_instance_name
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl delete secret datadog-secret --namespace $NAMESPACE --ignore-not-found
    kubectl delete secret cloudprem-metastore-uri --namespace $NAMESPACE --ignore-not-found
    kubectl delete namespace $NAMESPACE --ignore-not-found
    EOT
    environment = {
      CLUSTER_NAME = self.triggers_replace[0]
      NAMESPACE    = self.triggers_replace[1]
    }
  }

}

# CloudPrem registers itself with Datadog's control plane when the searcher pods dial out
# over the reverse WebSocket (CP_ENABLE_REVERSE_CONNECTION). Neither `helm uninstall` nor
# `kubectl delete namespace` removes that registration -- the chart has only create-time jobs
# (job-create-indices, job-create-sources) and no pre-delete hook -- so destroyed labs
# accumulate "Inactive" rows on the BYOC Logs Clusters page indefinitely. This resource
# exists only to carry a destroy-time provisioner that deletes the registration.
#
# The two depends_on edges look backwards because Terraform destroys dependents first:
#   - helm_release.cloudprem depends on this resource, so the release is uninstalled first
#   - this resource depends on module.datadog_secrets, so it runs before those are deleted
#     (recovery_window_in_days = 0) and, transitively, before datadog_api_key.this is
#     revoked -- the secrets module consumes those keys via secret_string_wo
# Net destroy order: helm uninstall -> deregister -> secrets -> Datadog keys.
#
# The endpoint is /api/unstable/, so it carries no compatibility guarantee: every failure
# path warns and exits 0 rather than blocking a destroy. Requires jq, already a de facto
# dependency of this repo.
resource "terraform_data" "cloudprem_deregister" {
  count      = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  depends_on = [module.datadog_secrets]

  # Destroy-time provisioners may only reference self, so every value the script needs is
  # carried here -- deliberately excluding the keys themselves, both to keep credentials out
  # of state and because a key rotation would otherwise replace this resource and deregister
  # a live cluster. The script reads them from Secrets Manager at destroy time instead.
  # These names reproduce module.datadog_secrets's own name expression.
  triggers_replace = {
    site           = var.datadog_site
    cluster_id     = local.cloudprem.cluster_id
    region         = data.aws_region.current.region
    api_key_secret = "${var.prefix}-${var.uid}-${local.module}-api-key-cloudprem"
    app_key_secret = "${var.prefix}-${var.uid}-${local.module}-app-key-kubernetes-operator"
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = <<-EOT
    set +e
    API_KEY=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$API_KEY_SECRET" --query SecretString --output text 2>/dev/null)
    APP_KEY=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$APP_KEY_SECRET" --query SecretString --output text 2>/dev/null)
    if [ -z "$API_KEY" ] || [ -z "$APP_KEY" ]; then
      echo "WARNING: Datadog keys unavailable; leaving BYOC cluster $CLUSTER_ID registered" >&2
      exit 0
    fi
    BASE="https://api.$DD_SITE/api/unstable/logs/cloudprem/clusters"
    # Match on prefix, not equality: the control plane appends a suffix (e.g. -7ef62641) when
    # a cluster_id collides, so a destroy also sweeps up rows leaked by earlier applies of
    # this same lab. The prefix is this lab's own cluster_id, which is what makes the delete
    # safe -- connection_status is reported but never used to skip, since right after the
    # uninstall the control plane may not have timed out the connection yet.
    MATCHES=$(curl -sS -m 30 -H "DD-API-KEY: $API_KEY" -H "DD-APPLICATION-KEY: $APP_KEY" "$BASE" \
      | jq -r --arg p "$CLUSTER_ID" '.clusters[]? | select(.name | startswith($p)) | "\(.id) \(.connection_status)"')
    if [ -z "$MATCHES" ]; then
      echo "No BYOC cluster registration matching $CLUSTER_ID; nothing to deregister"
      exit 0
    fi
    echo "$MATCHES" | while read -r ID STATUS; do
      [ -z "$ID" ] && continue
      if [ "$STATUS" != "reverse_inactive" ]; then
        echo "WARNING: BYOC cluster $ID still reports $STATUS; deleting anyway" >&2
      fi
      CODE=$(curl -sS -o /dev/null -w '%%{http_code}' -m 30 -X DELETE \
        -H "DD-API-KEY: $API_KEY" -H "DD-APPLICATION-KEY: $APP_KEY" "$BASE/$ID")
      echo "Deregistered BYOC cluster $ID (was $STATUS, HTTP $CODE)"
    done
    exit 0
    EOT
    environment = {
      DD_SITE        = self.triggers_replace.site
      CLUSTER_ID     = self.triggers_replace.cluster_id
      REGION         = self.triggers_replace.region
      API_KEY_SECRET = self.triggers_replace.api_key_secret
      APP_KEY_SECRET = self.triggers_replace.app_key_secret
    }
  }
}

module "cloudprem_db" {
  count   = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.prefix}-${var.uid}-${local.module}-cloudprem"

  engine            = "postgres"
  engine_version    = "17.6"
  family            = "postgres17"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name                     = "cloudprem"
  username                    = "cloudprem"
  password                    = random_password.cloudprem_db[0].result
  manage_master_user_password = false # disable automatic password rotation via Secrets Manager

  db_subnet_group_name   = data.aws_vpc.quicklab[0].id
  create_db_subnet_group = true
  subnet_ids             = data.aws_subnets.private[0].ids # []
  vpc_security_group_ids = [module.cloudprem_security_group[0].security_group_id]

  backup_retention_period = 0
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = merge(local.cloud_resource_tags, {})
}

resource "random_password" "cloudprem_db" {
  count  = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  length = 8
}

module "cloudprem_security_group" {
  count   = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.3.1"

  name        = "${var.prefix}-${var.uid}-${local.module}-cloudprem-db-sg"
  description = "Complete PostgreSQL example security group"
  vpc_id      = var.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = data.aws_vpc.quicklab[0].cidr_block
    },
  ]

  tags = { Name = join("-", [var.prefix, var.uid, "sg-postgres"]) }
}

resource "aws_s3_bucket" "cloudprem" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  bucket        = "${var.prefix}-${var.uid}-${local.module}-cloudprem-${data.aws_region.current.region}"
  force_destroy = true

  tags = merge(local.cloud_resource_tags,
    {
      Name    = "${var.prefix}-${var.uid}-cloudprem"
      service = "cloudprem"
    }
  )
}

resource "aws_s3_bucket_public_access_block" "cloudprem" {
  count  = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  bucket = aws_s3_bucket.cloudprem[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudprem" {
  count  = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  bucket = aws_s3_bucket.cloudprem[0].id

  rule {
    id     = "default retention"
    status = "Enabled"
    expiration { days = var.cloudprem_retention }
    filter {} # applies to all bucket objects
  }
}

resource "aws_iam_policy" "cloudprem" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  name        = "${var.prefix}-${var.uid}-${local.module}-cloudprem-policy"
  path        = "/"
  description = "CloudPrem IAM Policy for S3 access. Ref: https://docs.datadoghq.com/cloudprem/configure/aws_config/#iam-permissions-for-s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cloudprem[0].arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "${aws_s3_bucket.cloudprem[0].arn}/*"
        ]
      }
    ]
  })

  tags = merge(local.cloud_resource_tags, {})
}

resource "aws_iam_role" "cloudprem_pod_identity" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  name = "${var.prefix}-${var.uid}-${local.module}-cloudprem-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = merge(local.cloud_resource_tags, {})
}

resource "aws_iam_role_policy_attachment" "cloudprem" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  policy_arn = aws_iam_policy.cloudprem[0].arn
  role       = aws_iam_role.cloudprem_pod_identity[0].name
}

resource "aws_eks_pod_identity_association" "cloudprem" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.cloudprem.namespace
  service_account = "${var.prefix}-${var.uid}-${local.module}-cloudprem"
  role_arn        = aws_iam_role.cloudprem_pod_identity[0].arn

  tags = merge(local.cloud_resource_tags, {})
}

resource "terraform_data" "cloudprem_alb_exists" {
  count      = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  depends_on = [helm_release.cloudprem]

  # aws-load-balancer-controller provisions the ALB asynchronously after helm_release.cloudprem
  # completes, and data.aws_lb has no built-in retry on "not found" (see
  # https://github.com/hashicorp/terraform-provider-aws/issues/40520). A local-exec provisioner
  # gated by depends_on is the HashiCorp-recommended workaround for this gap, per
  # https://github.com/hashicorp/terraform-provider-aws/issues/26026. Poll only for the ALB's
  # existence/discoverability by tag: dns_name is assigned at creation time, before the ALB
  # reaches "active" state, and nothing downstream needs more than the DNS name.
  provisioner "local-exec" {
    command = <<-EOT
    set -euo pipefail
    ATTEMPTS=0
    MAX_ATTEMPTS=30
    while true; do
      ARN=$(aws resourcegroupstaggingapi get-resources \
        --region "$REGION" \
        --resource-type-filters elasticloadbalancing:loadbalancer \
        --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER_NAME" "Key=ingress.k8s.aws/stack,Values=$STACK_TAG" "Key=ingress.k8s.aws/resource,Values=LoadBalancer" \
        --query 'ResourceTagMappingList[0].ResourceARN' --output text 2>/dev/null || echo "None")
      if [ "$ARN" != "None" ] && [ -n "$ARN" ]; then
        echo "CloudPrem ALB found: $ARN"
        break
      fi
      ATTEMPTS=$((ATTEMPTS + 1))
      if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
        echo "Timed out waiting for CloudPrem ALB to become discoverable via tags" >&2
        exit 1
      fi
      sleep 10
    done
    EOT
    environment = {
      REGION       = data.aws_region.current.region
      CLUSTER_NAME = var.cluster_name
      STACK_TAG    = "${local.cloudprem.namespace}/cloudprem-internal"
    }
  }
}

data "aws_lb" "cloudprem_ingress" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "ingress.k8s.aws/stack"    = "${local.cloudprem.namespace}/cloudprem-internal"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [terraform_data.cloudprem_alb_exists]
}

resource "aws_secretsmanager_secret" "cloudprem_ingress_endpoint" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  name  = "${var.prefix}-${var.uid}-cloudprem-ingress-endpoint"
  tags  = var.cloud_resource_tags
}

resource "aws_secretsmanager_secret_version" "cloudprem_ingress_endpoint" {
  count         = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  secret_id     = aws_secretsmanager_secret.cloudprem_ingress_endpoint[0].id
  secret_string = data.aws_lb.cloudprem_ingress[0].dns_name
}

/*

#! REFERENCE

# Micro RDS instance for testing purposes. Takes around 5 min.
aws rds create-db-instance 
 --db-instance-identifier cloudprem-postgres 
 --db-instance-class db.t3.micro 
 --engine postgres 
 --engine-version 16.3 
 --master-username cloudprem 
 --master-user-password 'FixMeCloudPrem' 
 --allocated-storage 20 
 --storage-type gp3 
 --db-subnet-group-name <VPC-ID> 
 --vpc-security-group-ids <VPC-SECURITY-GROUP-ID> 
 --db-name cloudprem 
 --backup-retention-period 0 
 --no-multi-az

*/

/*

#! UNUSED

resource "local_file" "cloudprem_values" {

  content = templatefile("",
    # SERVICE_ACCOUNT_EKS_ROLE_NAME = "${var.prefix}-${var.uid}-${local.module}-cloudprem" # disable to use Pod Identity
  )
}

## cloudprem-values.tftpl

serviceAccount:
  eksRoleName: ${SERVICE_ACCOUNT_EKS_ROLE_NAME} # removing to use Pod Identity instead of IRSA

*/
