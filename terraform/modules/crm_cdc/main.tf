terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  prefix = "zaki-lakehouse-dbt-${var.environment}"
}

# The default VPC keeps this demo small. Check it exists with:
#   aws ec2 describe-vpcs --filters Name=isDefault,Values=true
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "dms" {
  name        = "${local.prefix}-dms"
  description = "DMS replication instance"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound (database and S3)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.prefix}-crm-db"
  description = "CRM database"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL from the DMS replication instance"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.dms.id]
  }

  dynamic "ingress" {
    for_each = var.admin_cidr == "" ? [] : [var.admin_cidr]

    content {
      description = "PostgreSQL from the admin laptop"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
}

# ---------------------------------------------------------------------------
# CRM database (PostgreSQL with logical replication enabled for CDC)
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "crm" {
  name       = "${local.prefix}-crm"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_parameter_group" "crm" {
  name   = "${local.prefix}-crm-pg16"
  family = "postgres16"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_sender_timeout"
    value = "0"
  }
}

resource "aws_db_instance" "crm" {
  identifier             = "${local.prefix}-crm"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "crm"
  username               = "crm_admin"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.crm.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.crm.name
  publicly_accessible    = var.admin_cidr != ""

  backup_retention_period    = 1
  skip_final_snapshot        = true
  deletion_protection        = false
  apply_immediately          = true
  auto_minor_version_upgrade = true
}

# Credentials for the seed script (read with your own AWS login, never committed).
resource "aws_secretsmanager_secret" "crm" {
  name                    = "${local.prefix}-crm-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "crm" {
  secret_id = aws_secretsmanager_secret.crm.id
  secret_string = jsonencode({
    username = aws_db_instance.crm.username
    password = random_password.db.result
    host     = aws_db_instance.crm.address
    port     = aws_db_instance.crm.port
    dbname   = aws_db_instance.crm.db_name
  })
}

# ---------------------------------------------------------------------------
# Role DMS uses to write into the raw bucket
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dms_s3" {
  name               = "${local.prefix}-dms-s3"
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
}

data "aws_iam_policy_document" "dms_s3" {
  statement {
    sid = "WriteChangeFiles"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
    ]
    resources = ["arn:aws:s3:::${var.raw_bucket_name}/crm/*"]
  }

  statement {
    sid = "ListBucket"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = ["arn:aws:s3:::${var.raw_bucket_name}"]
  }
}

resource "aws_iam_role_policy" "dms_s3" {
  name   = "write-raw-crm"
  role   = aws_iam_role.dms_s3.id
  policy = data.aws_iam_policy_document.dms_s3.json
}

# ---------------------------------------------------------------------------
# DMS: replication instance, endpoints and the full-load + CDC task
# ---------------------------------------------------------------------------

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${local.prefix}-dms"
  replication_subnet_group_description = "Subnets for the ${var.environment} DMS replication instance"
  subnet_ids                           = data.aws_subnets.default.ids
}

resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = "${local.prefix}-dms"
  replication_instance_class  = "dms.t3.micro"
  allocated_storage           = 20
  multi_az                    = false
  publicly_accessible         = true
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  vpc_security_group_ids      = [aws_security_group.dms.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.id
}

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${local.prefix}-crm-source"
  endpoint_type = "source"
  engine_name   = "postgres"
  server_name   = aws_db_instance.crm.address
  port          = 5432
  database_name = "crm"
  username      = aws_db_instance.crm.username
  password      = random_password.db.result
  ssl_mode      = "require"
}

resource "aws_dms_s3_endpoint" "target" {
  endpoint_id             = "${local.prefix}-raw-target"
  endpoint_type           = "target"
  bucket_name             = var.raw_bucket_name
  bucket_folder           = "crm"
  service_access_role_arn = aws_iam_role.dms_s3.arn

  data_format                      = "parquet"
  parquet_timestamp_in_millisecond = true
  include_op_for_full_load         = true
  timestamp_column_name            = "cdc_ts"

  depends_on = [aws_iam_role_policy.dms_s3]
}

resource "aws_dms_replication_task" "customers" {
  replication_task_id      = "${local.prefix}-crm-customers"
  migration_type           = "full-load-and-cdc"
  replication_instance_arn = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_s3_endpoint.target.endpoint_arn
  start_replication_task   = false

  table_mappings = jsonencode({
    rules = [
      {
        "rule-type" = "selection"
        "rule-id"   = "1"
        "rule-name" = "include-customers"
        "object-locator" = {
          "schema-name" = "public"
          "table-name"  = "customers"
        }
        "rule-action" = "include"
      }
    ]
  })
}
