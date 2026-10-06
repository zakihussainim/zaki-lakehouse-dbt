variable "environment" {
  description = "Deployment environment, for example dev or prod"
  type        = string
}

variable "raw_bucket_name" {
  description = "Bucket holding the raw landing data"
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Bucket holding the Iceberg tables"
  type        = string
}

variable "athena_results_bucket_name" {
  description = "Bucket for Athena query results"
  type        = string
}
