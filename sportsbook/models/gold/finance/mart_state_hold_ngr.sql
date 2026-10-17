{# EXERCISE 4: hold % and NGR by state (simplified, illustrative tax logic) #}
with f as (select * from {{ ref('fct_bets') }} where status = 'settled'),
tax as (select * from {{ from_landing('state_tax_rates') }}),
agg as (
    select
        state,
        count(*)                       as settled_bets,
        sum(cash_handle)               as cash_handle,
        sum(cash_ggr)                  as cash_ggr,
        sum(bonus_cost)                as bonus_cost
    from f
    group by state
)
select
    a.state,
    a.settled_bets,
    a.cash_handle,
    a.cash_ggr,
    round(a.cash_ggr / nullif(a.cash_handle, 0), 4)                      as hold_pct,
    a.bonus_cost,
    a.cash_ggr - a.bonus_cost                                            as ngr,
    t.osb_tax_rate,
    case when t.promo_deductible_toy then a.cash_ggr - a.bonus_cost
         else a.cash_ggr end                                             as taxable_base,
    round(greatest(case when t.promo_deductible_toy then a.cash_ggr - a.bonus_cost
                        else a.cash_ggr end, 0) * t.osb_tax_rate, 2)     as est_gaming_tax,
    round(a.cash_ggr - a.bonus_cost
          - greatest(case when t.promo_deductible_toy then a.cash_ggr - a.bonus_cost
                          else a.cash_ggr end, 0) * t.osb_tax_rate, 2)   as ngr_after_tax
from agg a
left join tax t on t.state = a.state
order by a.state
