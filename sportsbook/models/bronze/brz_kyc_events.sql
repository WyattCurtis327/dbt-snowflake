{# Bronze: 1:1 with landing.raw_kyc_events — rename/cast only. #}
select
    customer_id,
    upper(state)                     as state,
    lower(event_name)                as event_name,
    cast(event_ts_utc as timestamp)  as event_ts_utc
from {{ from_landing('raw_kyc_events') }}
