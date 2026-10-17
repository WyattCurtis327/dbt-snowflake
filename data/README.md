# FBG prep: mock sportsbook dataset (100% fake)

Synthetic data for practicing Snowflake + dbt. 500 fake customers (C0001-C0500) across 15 states,
Aug 1 - Oct 16 2026, frozen "as of" **2026-10-17 04:00 UTC**. Games, lines and scores are simulated
(only the team abbreviations are real). All timestamps are UTC. Promo names start with "MOCK".
Load into Snowflake: run `../snowflake/day1_setup.sql` first, then `../snowflake/load_mock_data.sql`.
Upload the CSVs in this folder to `FBG_PREP.LANDING.MOCK_STAGE`. Landing is the first stop after PUT/COPY; it is not bronze.

| File | Rows | Grain / what it's for |
|---|---|---|
| raw_customers.csv | 500 | current customer record; vip_tier is overwritten (Ex 2), 5 test accounts |
| raw_customers_v1.csv | 500 | same customers as of 10/15 00:00 UTC extract (Ex 2 snapshot replay, Day 1) |
| raw_vip_tier_history.csv | 219 | one row per tier change (event-sourced SCD2 alternative) |
| raw_bets.csv | 11,641 | one row per bet; legs_json array (22,722 legs); single/parlay/sgp; settled/void/open; 597 bonus bets |
| raw_payments.csv | 3,140 | deposits + withdrawals, current state (Day 2) |
| raw_payments_batch1.csv | 2,974 | 10/15 extract (Day 1): later status changes not yet applied, 15 late-arriving rows missing |
| raw_kyc_events.csv | 1,944 | registered / kyc_submitted / kyc_failed / kyc_passed / first_deposit (Ex 6) |
| raw_cx_tickets.csv | 1,043 (973 tickets) | Zendesk-style; reload duplicates on ticket_id + messy channel casing on purpose |
| raw_fraud_alerts.csv | 82 | velocity, chargeback, multi-account, bonus abuse, ATO, geo, high-value WD, and 'test' rows |
| raw_promos.csv | 6 | promo definitions (bonus bets, no-sweat SGP, deposit match, VIP reload, FanCash) |
| raw_promo_awards.csv | 1,913 | bonus-bet tokens (redeemed_bet_id -> raw_bets) and FanCash credits |
| state_tax_rates.csv | 15 | approximate headline online rates; TN taxes handle (tax_basis column). Verify before quoting |

Planted teaching moments (all verified in DuckDB):
- Ex 1: 2 bets have `legs_json = []` and vanish from a plain LATERAL FLATTEN (use OUTER => TRUE). 1,716 parlays/SGPs lost by exactly one leg.
- Ex 2: 26 customers change tier between the v1 and current loads; 2 of them changed twice, and a snapshot only sees the last change.
  Attribution trap: platinum is $62k of handle at bet-time tier vs $505k if you join on current tier.
- Ex 3: naive `updated_at >= max(updated_at)` incremental drops 15 late-arriving deposits (3,125 vs 3,140 rows); 8 Aug/Sep card deposits flip to `chargeback` with a new updated_at.
- Ex 4: overall cash hold 11.5% (singles 6.6%, SGP 26.9%, parlays 33.7%). Test accounts' bets are excluded (they *won* $6.7k). TN tax is on handle, so the course formula undercounts it.
- Ex 5: 11 pending withdrawals; 7 match "older than 24h or gold/platinum" at the as-of time.
- Ex 6: 163 of 500 registrations fall on a different calendar day in ET than in UTC.
- CX: dedupe with `qualify row_number() over (partition by ticket_id order by _loaded_at desc) = 1`, then `lower(trim(channel))` -> chat/email/phone.

Not modeled: account balances don't reconcile deposits against bets, there's no cash-out or live betting, and the FanCash and no-sweat costs aren't in the course's NGR formula.
