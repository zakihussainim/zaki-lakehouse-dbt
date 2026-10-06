variable "environment" {
  description = "Deployment environment, for example dev or prod"
  type        = string
}

variable "raw_bucket_name" {
  description = "Bucket DMS writes the change files to (under crm/)"
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP as a /32 CIDR, allowed to reach the database from your laptop. Empty means the database is private."
  type        = string
  default     = ""
}
