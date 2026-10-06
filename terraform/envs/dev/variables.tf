variable "admin_cidr" {
  description = "Your public IP as a /32 CIDR so you can reach the CRM database from your laptop (set via the ADMIN_CIDR GitHub Variable). Empty keeps the database private."
  type        = string
  default     = ""
}
