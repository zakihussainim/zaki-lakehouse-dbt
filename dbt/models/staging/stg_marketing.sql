-- Each marketing drop is a full snapshot, so the newest file wins per customer.
with source as (

    select
        customer_id,
        marketing_opt_in,
        preferred_channel,
        postal_address,
        updated_at,
        "$path" as source_file
    from {{ source('raw', 'marketing_raw') }}

),

typed as (

    select
        trim(customer_id) as customer_id,
        lower(marketing_opt_in) = 'true' as marketing_opt_in,
        lower(preferred_channel) as preferred_channel,
        postal_address,
        cast(try(from_iso8601_timestamp(updated_at)) as timestamp) as updated_at,
        source_file
    from source
    where customer_id is not null
      and trim(customer_id) <> ''

),

ranked as (

    select
        *,
        row_number() over (partition by customer_id order by source_file desc) as drop_rank
    from typed

)

select
    customer_id,
    marketing_opt_in,
    preferred_channel,
    postal_address,
    updated_at,
    source_file
from ranked
where drop_rank = 1
