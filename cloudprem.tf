data "aws_vpc" "quicklab" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  id    = var.vpc_id
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
  count      = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  depends_on = [terraform_data.cloudprem_secrets, module.cloudprem_db, local_file.cloudprem_values]

  name       = local.cloudprem.helm_release
  repository = "https://helm.datadoghq.com/" # https://artifacthub.io/packages/helm/datadog/"
  chart      = "cloudprem"
  version    = "0.1.14"

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
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0
  # depends_on       = [module.quicklab_cluster, helm_release.karpenter] 
  triggers_replace = [var.cluster_name, local.cloudprem.namespace]

  provisioner "local-exec" {
    command = <<-EOT
    export KUBECONFIG=~/.kube/$CLUSTER_NAME
    kubectl create namespace $NAMESPACE
    kubectl create secret generic datadog-secret --namespace $NAMESPACE --from-literal api-key=$DD_API_KEY
    kubectl create secret generic cloudprem-metastore-uri --namespace $NAMESPACE --from-literal QW_METASTORE_URI="postgres://$USERNAME:$PASSWORD@$ADDRESS:$PORT/$DATABASE"
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

data "aws_lb" "cloudprem_ingress" {
  count = local.quicklab_cluster_enabled && var.create_byoc_k8s_deployments ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "ingress.k8s.aws/stack"    = "${local.cloudprem.namespace}/cloudprem-internal"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }

  depends_on = [helm_release.cloudprem]
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
