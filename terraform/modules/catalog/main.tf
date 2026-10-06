locals {
  # Column lists are mirrored in src/datagen (tests/test_contracts.py fails if they drift).
  orders_columns = [
    "order_id",
    "customer_id",
    "order_ts",
    "product_sku",
    "quantity",
    "unit_price",
    "status",
  ]

  marketing_columns = [
    "customer_id",
    "marketing_opt_in",
    "preferred_channel",
    "postal_address",
    "updated_at",
  ]

  crm_columns = {
    op             = "string"
    cdc_ts         = "string"
    customer_id    = "string"
    full_name      = "string"
    email          = "string"
    phone          = "string"
    segment        = "string"
    postal_address = "string"
    updated_at     = "timestamp"
  }
}

# ---------------------------------------------------------------------------
# Glue databases
# ---------------------------------------------------------------------------

resource "aws_glue_catalog_database" "raw" {
  name = "lakehouse_raw_${var.environment}"
}

resource "aws_glue_catalog_database" "curated" {
  name         = "lakehouse_${var.environment}"
  location_uri = "s3://${var.lakehouse_bucket_name}/"
}

# ---------------------------------------------------------------------------
# Raw external tables (read-only views over files in the raw bucket)
# ---------------------------------------------------------------------------

resource "aws_glue_catalog_table" "orders_raw" {
  name          = "orders_raw"
  database_name = aws_glue_catalog_database.raw.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                 = "TRUE"
    "skip.header.line.count" = "1"
    classification           = "csv"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket_name}/orders/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"

      parameters = {
        separatorChar = ","
        quoteChar     = "\""
        escapeChar    = "\\"
      }
    }

    dynamic "columns" {
      for_each = local.orders_columns

      content {
        name = columns.value
        type = "string"
      }
    }
  }
}

resource "aws_glue_catalog_table" "marketing_raw" {
  name          = "marketing_raw"
  database_name = aws_glue_catalog_database.raw.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                 = "TRUE"
    "skip.header.line.count" = "1"
    classification           = "csv"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket_name}/marketing/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"

      parameters = {
        separatorChar = ","
        quoteChar     = "\""
        escapeChar    = "\\"
      }
    }

    dynamic "columns" {
      for_each = local.marketing_columns

      content {
        name = columns.value
        type = "string"
      }
    }
  }
}

# DMS writes Parquet files here: <bucket_folder>/<schema>/<table>/ = crm/public/customers/
resource "aws_glue_catalog_table" "crm_customers_raw" {
  name          = "crm_customers_raw"
  database_name = aws_glue_catalog_database.raw.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL       = "TRUE"
    classification = "parquet"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket_name}/crm/public/customers/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.crm_columns

      content {
        name = columns.key
        type = columns.value
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Athena workgroup (engine v3 is required for Iceberg)
# ---------------------------------------------------------------------------

resource "aws_athena_workgroup" "this" {
  name          = "zaki-lakehouse-dbt-${var.environment}"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false
    bytes_scanned_cutoff_per_query     = 1073741824

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.athena_results_bucket_name}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
