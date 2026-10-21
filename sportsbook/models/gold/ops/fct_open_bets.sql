{{ config(materialized='table') }}

select
    bet_id,
    customer_id,
    state,
    bet_type,
    stake,
    placed_at_utc,
    {{ to_et('placed_at_utc') }} as placed_at_et
from {{ ref('brz_bets') }}
where status = 'open'