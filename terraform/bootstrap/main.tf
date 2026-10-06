terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = "eu-west-2"
  project    = "zaki-lakehouse-dbt"

  # Data buckets are named <project>-<env>-<purpose>-<account>. The pattern
  # deliberately does NOT match the state bucket (<project>-tfstate-<account>).
  env_bucket_arns = [
    "arn:aws:s3:::${local.project}-dev-*",
    "arn:aws:s3:::${local.project}-dev-*/*",
    "arn:aws:s3:::${local.project}-prod-*",
    "arn:aws:s3:::${local.project}-prod-*/*",
  ]

  # Roles created by the environments. Does NOT match the CI role itself
  # (<project>-github-actions-deploy), so CI cannot edit its own permissions.
  env_role_arns = [
    "arn:aws:iam::${local.account_id}:role/${local.project}-dev-*",
    "arn:aws:iam::${local.account_id}:role/${local.project}-prod-*",
  ]

  glue_arns = [
    "arn:aws:glue:${local.region}:${local.account_id}:catalog",
    "arn:aws:glue:${local.region}:${local.account_id}:database/default",
    "arn:aws:glue:${local.region}:${local.account_id}:database/lakehouse_*",
    "arn:aws:glue:${local.region}:${local.account_id}:table/lakehouse_*/*",
    "arn:aws:glue:${local.region}:${local.account_id}:userDefinedFunction/lakehouse_*/*",
  ]

  athena_arns = [
    "arn:aws:athena:${local.region}:${local.account_id}:workgroup/${local.project}-*",
    "arn:aws:athena:${local.region}:${local.account_id}:datacatalog/AwsDataCatalog",
  ]

  rds_arns = [
    "arn:aws:rds:${local.region}:${local.account_id}:db:${local.project}-*",
    "arn:aws:rds:${local.region}:${local.account_id}:subgrp:${local.project}-*",
    "arn:aws:rds:${local.region}:${local.account_id}:pg:${local.project}-*",
    "arn:aws:rds:${local.region}:${local.account_id}:og:default:*",
  ]
}

# ---------------------------------------------------------------------------
# S3 bucket that holds Terraform state
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = "${local.project}-tfstate-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# GitHub Actions -> AWS (OIDC)
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:zakihussainim@290070594/zaki-lakehouse-dbt@1388173970:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "${local.project}-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

# ---------------------------------------------------------------------------
# What the CI role may do
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid = "ReadWriteTerraformState"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]
  }

  statement {
    sid       = "ManageEnvironmentBuckets"
    actions   = ["s3:*"]
    resources = local.env_bucket_arns
  }

  statement {
    sid       = "ManageGlueCatalog"
    actions   = ["glue:*"]
    resources = local.glue_arns
  }

  statement {
    sid       = "ManageAthena"
    actions   = ["athena:*"]
    resources = local.athena_arns
  }

  statement {
    sid = "AthenaCatalogRead"
    actions = [
      "athena:GetDataCatalog",
      "athena:ListDataCatalogs",
      "athena:GetDatabase",
      "athena:ListDatabases",
      "athena:GetTableMetadata",
      "athena:ListTableMetadata",
      "athena:ListWorkGroups",
    ]
    resources = ["*"]
  }

  statement {
    sid = "DescribeNetworkAndDatabases"
    actions = [
      "ec2:Describe*",
      "rds:Describe*",
      "rds:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageSecurityGroups"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ManageRds"
    actions   = ["rds:*"]
    resources = local.rds_arns
  }

  statement {
    sid       = "ManageDms"
    actions   = ["dms:*"]
    resources = ["*"]
  }

  statement {
    sid       = "ManageSecrets"
    actions   = ["secretsmanager:*"]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${local.project}-*"]
  }

  statement {
    sid = "ManageEnvironmentRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = local.env_role_arns
  }

  statement {
    sid       = "PassEnvironmentRolesToDms"
    actions   = ["iam:PassRole"]
    resources = local.env_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["dms.amazonaws.com"]
    }
  }

  statement {
    sid       = "RdsServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["rds.amazonaws.com"]
    }
  }

  statement {
    sid = "KmsViaRdsAndSecretsManager"
    actions = [
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "rds.${local.region}.amazonaws.com",
        "secretsmanager.${local.region}.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "github_actions_permissions" {
  name   = "${local.project}-github-actions-permissions"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

# ---------------------------------------------------------------------------
# Account-level service roles that AWS DMS requires (exact names are mandatory)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "dms_service_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dms_vpc" {
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms_vpc.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch_logs" {
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs" {
  role       = aws_iam_role.dms_cloudwatch_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}
