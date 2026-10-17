{# Bronze: 1:1 with landing.raw_payments — rename/cast only. #}
select
    payment_id,
    customer_id,
    lower(payment_type)                as payment_type,
    lower(method)                      as method,
    cast(amount as decimal(18,2))      as amount,
    lower(status)                      as status,
    cast(requested_at as timestamp)    as requested_at,
    cast(completed_at as timestamp)    as completed_at,
    cast(updated_at as timestamp)      as updated_at
from {{ from_landing('raw_payments') }}
