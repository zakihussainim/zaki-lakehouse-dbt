{{ config(materialized='table', table_type='iceberg', format='parquet') }}

-- One row per customer, reconciled across CRM (database stream) and marketing (file drops).
-- Field ownership:
--   CRM owns       full_name, email, phone, segment
--   Marketing owns marketing_opt_in, preferred_channel
--   Shared         postal_address: the source with the newest updated_at wins
with crm as (

    select * from {{ ref('stg_crm_customers') }}

),

marketing as (

    select * from {{ ref('stg_marketing') }}

),

joined as (

    select
        coalesce(crm.customer_id, marketing.customer_id) as customer_id,
        crm.customer_id is not null as in_crm,
        marketing.customer_id is not null as in_marketing,
        crm.full_name,
        crm.email,
        crm.phone,
        crm.segment,
        marketing.marketing_opt_in,
        marketing.preferred_channel,
        crm.postal_address as crm_address,
        crm.updated_at as crm_updated_at,
        marketing.postal_address as marketing_address,
        marketing.updated_at as marketing_updated_at,
        coalesce(not crm.is_deleted, true) as is_active
    from crm
    full outer join marketing
        on crm.customer_id = marketing.customer_id

)

select
    customer_id,
    full_name,
    email,
    phone,
    segment,
    marketing_opt_in,
    preferred_channel,
    case
        when crm_address is null then marketing_address
        when marketing_address is null then crm_address
        when marketing_updated_at > crm_updated_at then marketing_address
        else crm_address
    end as postal_address,
    case
        when crm_address is null then 'marketing'
        when marketing_address is null then 'crm'
        when marketing_updated_at > crm_updated_at then 'marketing'
        else 'crm'
    end as address_source,
    (
        crm_address is not null
        and marketing_address is not null
        and crm_address <> marketing_address
    ) as address_conflict,
    crm_address,
    marketing_address,
    in_crm,
    in_marketing,
    is_active,
    cast(crm_updated_at as timestamp(6)) as crm_updated_at,
    cast(marketing_updated_at as timestamp(6)) as marketing_updated_at
from joined
