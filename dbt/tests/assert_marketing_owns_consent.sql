-- Field ownership rule: where a customer exists in marketing, marketing's consent and
-- channel always win. Any returned row is a violation.
select
    d.customer_id
from {{ ref('dim_customer') }} as d
inner join {{ ref('stg_marketing') }} as m
    on d.customer_id = m.customer_id
where d.marketing_opt_in <> m.marketing_opt_in
   or d.preferred_channel <> m.preferred_channel
