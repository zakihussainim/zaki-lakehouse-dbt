locals {
  environment = "dev"

  # Flip to true to build the RDS + DMS change-data-capture stack.
  # It costs money while it exists. Flip back to false and merge to tear it down.
  enable_crm_cdc = false
}

module "storage" {
  source      = "../../modules/storage"
  environment = local.environment
}

module "catalog" {
  source                     = "../../modules/catalog"
  environment                = local.environment
  raw_bucket_name            = module.storage.raw_bucket_name
  lakehouse_bucket_name      = module.storage.lakehouse_bucket_name
  athena_results_bucket_name = module.storage.athena_results_bucket_name
}

module "crm_cdc" {
  count           = local.enable_crm_cdc ? 1 : 0
  source          = "../../modules/crm_cdc"
  environment     = local.environment
  raw_bucket_name = module.storage.raw_bucket_name
  admin_cidr      = var.admin_cidr
}
