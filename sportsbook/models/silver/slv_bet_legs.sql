{# Silver: explode parlay legs (one row per leg). Exercise 1. #}
{% if target.type == 'snowflake' %}
select
    b.bet_id,
    b.bet_type,
    l.index                                   as leg_index,
    l.value:event::string                     as event,
    l.value:market::string                    as market,
    l.value:selection::string                 as selection,
    l.value:american_odds::number             as american_odds,
    l.value:result::string                    as leg_result
from {{ ref('brz_bets') }} b,
     lateral flatten(input => parse_json(b.legs_json)) l
{% else %}
with exploded as (
    select b.bet_id, b.bet_type,
           unnest(from_json(b.legs_json, '["JSON"]')) as leg,
           generate_subscripts(from_json(b.legs_json, '["JSON"]'), 1) - 1 as leg_index
    from {{ ref('brz_bets') }} b
)
select
    bet_id,
    bet_type,
    leg_index,
    leg->>'event'                          as event,
    leg->>'market'                         as market,
    leg->>'selection'                      as selection,
    cast(leg->>'american_odds' as integer) as american_odds,
    leg->>'result'                         as leg_result
from exploded
{% endif %}
