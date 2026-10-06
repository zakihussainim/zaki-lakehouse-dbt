data "aws_caller_identity" "current" {}

locals {
  name_prefix = "zaki-lakehouse-dbt-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  buckets = {
    raw            = "${local.name_prefix}-raw-${local.account_id}"
    lakehouse      = "${local.name_prefix}-lakehouse-${local.account_id}"
    athena_results = "${local.name_prefix}-athena-results-${local.account_id}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = each.value
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.this["raw"].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.this["athena_results"].id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}
