output "raw_bucket_name" {
  value = module.storage.raw_bucket_name
}

output "lakehouse_bucket_name" {
  value = module.storage.lakehouse_bucket_name
}

output "athena_results_bucket_name" {
  value = module.storage.athena_results_bucket_name
}

output "athena_workgroup_name" {
  value = module.catalog.athena_workgroup_name
}

output "raw_database_name" {
  value = module.catalog.raw_database_name
}

output "curated_database_name" {
  value = module.catalog.curated_database_name
}
