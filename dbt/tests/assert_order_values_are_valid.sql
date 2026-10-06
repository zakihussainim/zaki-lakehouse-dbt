-- Orders must have a positive quantity and a non-negative price. Any returned row is a violation.
select
    order_id
from {{ ref('fct_orders') }}
where quantity is null
   or quantity <= 0
   or unit_price is null
   or unit_price < 0
