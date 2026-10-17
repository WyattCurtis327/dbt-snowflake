{# EXERCISE 2b: point-in-time join - which VIP tier was the customer in WHEN they placed the bet? #}
select
    f.bet_id, f.customer_id, f.placed_at_utc, f.stake,
    s.vip_tier as vip_tier_at_bet,
    c.vip_tier as vip_tier_now
from {{ ref('fct_bets') }} f
join {{ ref('snap_customer_vip') }} s
  on s.customer_id = f.customer_id
 and f.placed_at_utc >= s.dbt_valid_from
 and f.placed_at_utc <  s.dbt_valid_to          -- current rows carry 9999-12-31, so no COALESCE needed
join {{ ref('brz_customers') }} c on c.customer_id = f.customer_id
order by f.customer_id, f.placed_at_utc
