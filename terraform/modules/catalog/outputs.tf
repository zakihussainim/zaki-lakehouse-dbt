output "raw_database_name" {
  description = "Glue database holding the raw external tables"
  value       = aws_glue_catalog_database.raw.name
}

output "curated_database_name" {
  description = "Glue database dbt builds its models into"
  value       = aws_glue_catalog_database.curated.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup dbt and ad-hoc queries run in"
  value       = aws_athena_workgroup.this.name
}
