select
    state,
    count(*)                                              as registered,
    count(first_submit_at)                                as submitted_kyc,
    count(kyc_passed_at)                                  as passed_kyc,
    count(first_deposit_at)                               as made_ftd,
    sum(case when ftd_within_24h then 1 else 0 end)       as ftd_within_24h,
    round(count(kyc_passed_at) / count(first_submit_at)::double, 4) as kyc_pass_rate,
    median(minutes_to_kyc_pass)                           as median_min_to_pass
from {{ ref('fct_kyc_funnel') }}
group by state
order by state
