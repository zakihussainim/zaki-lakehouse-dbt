output "raw_bucket_name" {
  description = "Landing zone: CSV drops, marketing files and DMS output"
  value       = aws_s3_bucket.this["raw"].id
}

output "lakehouse_bucket_name" {
  description = "Iceberg tables written by dbt"
  value       = aws_s3_bucket.this["lakehouse"].id
}

output "athena_results_bucket_name" {
  description = "Athena query results (expire after 7 days)"
  value       = aws_s3_bucket.this["athena_results"].id
}
