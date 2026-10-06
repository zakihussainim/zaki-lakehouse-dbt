{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='order_id',
        table_type='iceberg',
        format='parquet',
        on_schema_change='append_new_columns'
    )
}}

-- One row per order. New files are merged in; duplicate rows (same order_id) collapse to one.
with orders as (

    select * from {{ ref('stg_orders') }}
    {% if is_incremental() %}
    where source_file > (select coalesce(max(source_file), '') from {{ this }})
    {% endif %}

),

deduplicated as (

    select
        *,
        row_number() over (partition by order_id order by source_file desc) as duplicate_rank
    from orders

)

select
    order_id,
    customer_id,
    cast(ordered_at as timestamp(6)) as ordered_at,
    product_sku,
    quantity,
    unit_price,
    quantity * unit_price as order_value,
    status,
    source_file
from deduplicated
where duplicate_rank = 1
