{# Bronze: 1:1 with landing.raw_customers — rename/cast only. #}
select
    customer_id,
    upper(state)                      as state,
    cast(signup_ts_utc as timestamp)  as signup_ts_utc,
    lower(vip_tier)                   as vip_tier,
    cast(is_test_account as boolean)  as is_test_account,
    cast(updated_at as timestamp)     as updated_at
from {{ from_landing('raw_customers') }}
