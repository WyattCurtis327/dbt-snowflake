{# Bronze: 1:1 with landing.raw_bets — rename/cast only. #}
select
    bet_id,
    customer_id,
    upper(state)                         as state,
    cast(placed_at_utc as timestamp)     as placed_at_utc,
    cast(settled_at_utc as timestamp)    as settled_at_utc,
    lower(bet_type)                      as bet_type,
    cast(stake as decimal(18,2))         as stake,
    cast(is_bonus_bet as boolean)        as is_bonus_bet,
    cast(payout as decimal(18,2))        as payout,      -- cash returned to customer (bonus bets: winnings only)
    lower(status)                        as status,
    legs_json                                             -- raw JSON string; on Snowflake land as VARIANT
from {{ from_landing('raw_bets') }}
