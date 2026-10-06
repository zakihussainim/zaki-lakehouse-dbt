-- Collapse the DMS change stream (I / U / D events) into one current row per customer.
-- Deletes are soft: the customer keeps its last known attributes and is_deleted = true.
with events as (

    select
        upper(op) as op,
        try_cast(cdc_ts as timestamp) as changed_at,
        customer_id,
        full_name,
        email,
        phone,
        segment,
        postal_address,
        updated_at
    from {{ source('raw', 'crm_customers_raw') }}

),

last_event as (

    select
        customer_id,
        op as last_op
    from (
        select
            customer_id,
            op,
            row_number() over (partition by customer_id order by changed_at desc) as event_rank
        from events
    ) as ranked_events
    where event_rank = 1

),

last_state as (

    select
        customer_id,
        full_name,
        email,
        phone,
        segment,
        postal_address,
        updated_at
    from (
        select
            *,
            row_number() over (partition by customer_id order by changed_at desc) as state_rank
        from events
        where op <> 'D'
    ) as ranked_states
    where state_rank = 1

)

select
    s.customer_id,
    s.full_name,
    s.email,
    s.phone,
    s.segment,
    s.postal_address,
    s.updated_at,
    e.last_op = 'D' as is_deleted
from last_state as s
inner join last_event as e
    on s.customer_id = e.customer_id
