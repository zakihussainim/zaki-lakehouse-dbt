{{ config(materialized='view') }}

-- Audit trail: every customer whose CRM and marketing addresses disagree, and which source won.
select
    customer_id,
    address_source,
    postal_address as winning_address,
    crm_address,
    crm_updated_at,
    marketing_address,
    marketing_updated_at
from {{ ref('dim_customer') }}
where address_conflict
