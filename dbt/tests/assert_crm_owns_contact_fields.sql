-- Field ownership rule: where a customer exists in the CRM, the CRM's value always wins
-- for name, email, phone and segment. Any returned row is a violation.
select
    d.customer_id
from {{ ref('dim_customer') }} as d
inner join {{ ref('stg_crm_customers') }} as c
    on d.customer_id = c.customer_id
where d.full_name <> c.full_name
   or d.email <> c.email
   or d.phone <> c.phone
   or d.segment <> c.segment
