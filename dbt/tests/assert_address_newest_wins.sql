-- Field ownership rule: when the two addresses disagree, the source with the newest
-- updated_at wins (CRM wins ties). Any returned row is a violation.
select
    customer_id
from {{ ref('dim_customer') }}
where address_conflict
  and (
      (marketing_updated_at > crm_updated_at and address_source <> 'marketing')
      or (marketing_updated_at <= crm_updated_at and address_source <> 'crm')
  )
