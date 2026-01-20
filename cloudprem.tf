data "aws_vpc" "quicklab" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

module "cloudprem_db" {
  count   = create_byoc_k8s_deployments ? 1 : 0
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "cloudprem-postgres"

  engine            = "postgres"
  engine_version    = "16.3"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = "cloudprem"
  username = "cloudprem"
  password = random_password.cloudprem_db[0].result

  # Network
  db_subnet_group_name   = try(data.aws_vpc.this.tags_all["Name"], "") # data.aws_vpc.quicklab.id
  create_db_subnet_group = true
  subnet_ids             = data.aws_subnets.private # []
  vpc_security_group_ids = [module.cloudprem_security_group[0].security_group_id]

  # Disable backups and multi-az (as specified)
  backup_retention_period = 0
  multi_az                = false

  # Skip final snapshot since backups are disabled
  skip_final_snapshot = true
  deletion_protection = false
}

resource "random_password" "cloudprem_db" {
  count  = create_byoc_k8s_deployments ? 1 : 0
  length = 8
}

module "cloudprem_security_group" {
  count   = create_byoc_k8s_deployments ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.3.1"

  name        = "${var.prefix}-${var.uid}-datadog-cloudprem-db-sg"
  description = "Complete PostgreSQL example security group"
  vpc_id      = var.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = data.aws_vpc.vpc_cidr_block
    },
  ]

  tags = { Name = join("-", [var.prefix, var.uid, "sg-postgres"]) }
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
