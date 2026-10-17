{{ config(materialized='table') }}
with bets as (select * from {{ ref('brz_bets') }}),
customers as (select * from {{ ref('brz_customers') }}),
legs as (
    select bet_id, count(*) as leg_count
    from {{ ref('slv_bet_legs') }}
    group by bet_id
)
select
    b.bet_id,
    b.customer_id,
    b.state,
    b.placed_at_utc,
    cast({{ to_et('b.placed_at_utc') }} as date)   as placed_date_et,
    b.settled_at_utc,
    cast({{ to_et('b.settled_at_utc') }} as date)  as settled_date_et,
    b.bet_type,
    l.leg_count,
    b.status,
    b.is_bonus_bet,
    b.stake,
    b.payout,
    -- cash handle = settled, non-void, real-money stakes
    case when b.status = 'settled' and not b.is_bonus_bet then b.stake else 0 end            as cash_handle,
    case when b.status = 'settled' and not b.is_bonus_bet then b.stake - b.payout else 0 end as cash_ggr,
    -- bonus bets: stake was "house money"; cost = winnings we paid out in cash
    case when b.status = 'settled' and b.is_bonus_bet then b.payout else 0 end               as bonus_cost
from bets b
join customers c on c.customer_id = b.customer_id
left join legs l on l.bet_id = b.bet_id
where not c.is_test_account           -- exclude internal/test accounts from every revenue metric
