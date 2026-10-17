{# EXERCISE 1b: parlays/SGPs that lost by exactly one leg (CX / promo-eligibility / "bad beat" analysis) #}
with legs as (select * from {{ ref('slv_bet_legs') }}),
bets as (select * from {{ ref('fct_bets') }})
select
    b.bet_id, b.customer_id, b.state, b.bet_type, b.stake,
    count(*)                                                  as legs,
    sum(case when l.leg_result = 'lost' then 1 else 0 end)    as lost_legs,
    round(exp(sum(ln({{ american_to_decimal('l.american_odds') }}))), 4) as parlay_decimal_odds
from bets b
join legs l on l.bet_id = b.bet_id
where b.bet_type in ('parlay', 'sgp') and b.status = 'settled'
group by 1,2,3,4,5
having sum(case when l.leg_result = 'lost' then 1 else 0 end) = 1
order by b.bet_id
