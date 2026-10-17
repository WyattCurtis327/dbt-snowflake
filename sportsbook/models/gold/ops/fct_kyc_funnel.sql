{# EXERCISE 6: KYC / onboarding funnel with ET reporting dates #}
with e as (select * from {{ ref('brz_kyc_events') }}),
per_customer as (
    select
        customer_id,
        state,
        min(case when event_name = 'registered'    then event_ts_utc end) as registered_at,
        min(case when event_name = 'kyc_submitted' then event_ts_utc end) as first_submit_at,
        min(case when event_name = 'kyc_passed'    then event_ts_utc end) as kyc_passed_at,
        sum(case when event_name = 'kyc_failed'    then 1 else 0 end)     as kyc_fail_count,
        min(case when event_name = 'first_deposit' then event_ts_utc end) as first_deposit_at
    from e
    group by 1, 2
)
select
    *,
    cast({{ to_et('registered_at') }} as date)                         as registered_date_et,
    cast(registered_at as date)                                        as registered_date_utc,
    datediff('minute', registered_at, kyc_passed_at)                   as minutes_to_kyc_pass,
    case when datediff('minute', first_submit_at, kyc_passed_at) <= 5
         then true else false end                                      as auto_passed_proxy,
    case when first_deposit_at <= registered_at + interval '24 hours'
         then true else false end                                      as ftd_within_24h
from per_customer
