output "credentials_secret_name" {
  description = "Secrets Manager secret holding the database login (read by src/datagen/crm.py)"
  value       = aws_secretsmanager_secret.crm.name
}

output "replication_task_id" {
  description = "DMS task that streams customer changes into the raw bucket"
  value       = aws_dms_replication_task.customers.replication_task_id
}
