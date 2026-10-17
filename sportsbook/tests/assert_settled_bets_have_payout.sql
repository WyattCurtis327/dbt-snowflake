-- Singular test: returns failing rows. A settled bet must have a non-null, non-negative payout.
select bet_id, status, payout
from {{ ref('fct_bets') }}
where status = 'settled' and (payout is null or payout < 0)
