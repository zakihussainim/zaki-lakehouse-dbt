with source as (

    select
        order_id,
        customer_id,
        order_ts,
        product_sku,
        quantity,
        unit_price,
        status,
        "$path" as source_file
    from {{ source('raw', 'orders_raw') }}

)

select
    trim(order_id) as order_id,
    trim(customer_id) as customer_id,
    cast(try(from_iso8601_timestamp(order_ts)) as timestamp) as ordered_at,
    product_sku,
    try_cast(quantity as integer) as quantity,
    try_cast(unit_price as decimal(10, 2)) as unit_price,
    lower(status) as status,
    source_file
from source
where order_id is not null
  and trim(order_id) <> ''
