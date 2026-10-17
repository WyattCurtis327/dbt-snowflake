select
    payment_type,
    method,
    count(*)                                                                   as attempts,
    sum(case when status = 'completed' then 1 else 0 end)                      as completed,
    round(sum(case when status = 'completed' then 1 else 0 end)
          / nullif(sum(case when status in ('completed','failed') then 1 else 0 end), 0), 4)
                                                                               as success_rate_resolved,
    sum(case when status = 'pending' then 1 else 0 end)                        as pending,
    round(median(hours_to_withdraw), 2)                                        as median_hours_to_withdraw
from {{ ref('fct_payments') }}
group by 1, 2
order by 1, 2
