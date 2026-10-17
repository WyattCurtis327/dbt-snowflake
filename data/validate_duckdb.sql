-- DuckDB mirror of snowflake_load_mock_data.sql: same tables, same types, read_csv ~= COPY INTO
-- run: python mock_data_gen/run_validation.py   (from /workspace/fanatics_prep; also works in the duckdb CLI)
CREATE SCHEMA raw;
CREATE TABLE raw.raw_customers AS SELECT * FROM read_csv('mock_data/raw_customers.csv', header=true, quote='"', escape='"', nullstr='', auto_detect=false,
  columns={'customer_id':'VARCHAR','state':'VARCHAR','signup_ts_utc':'TIMESTAMP','vip_tier':'VARCHAR','is_test_account':'BOOLEAN','updated_at':'TIMESTAMP'});
CREATE TABLE raw.raw_customers_v1 AS SELECT * FROM read_csv('mock_data/raw_customers_v1.csv', header=true, nullstr='', auto_detect=false,
  columns={'customer_id':'VARCHAR','state':'VARCHAR','signup_ts_utc':'TIMESTAMP','vip_tier':'VARCHAR','is_test_account':'BOOLEAN','updated_at':'TIMESTAMP'});
CREATE TABLE raw.raw_customers_v2 AS SELECT * FROM read_csv('mock_data/raw_customers.csv', header=true, nullstr='', auto_detect=false,
  columns={'customer_id':'VARCHAR','state':'VARCHAR','signup_ts_utc':'TIMESTAMP','vip_tier':'VARCHAR','is_test_account':'BOOLEAN','updated_at':'TIMESTAMP'});
CREATE TABLE raw.raw_vip_tier_history AS SELECT * FROM read_csv('mock_data/raw_vip_tier_history.csv', header=true, nullstr='', auto_detect=false,
  columns={'vip_change_id':'VARCHAR','customer_id':'VARCHAR','from_tier':'VARCHAR','to_tier':'VARCHAR','changed_at_utc':'TIMESTAMP','change_reason':'VARCHAR'});
CREATE TABLE raw.raw_bets AS SELECT * FROM read_csv('mock_data/raw_bets.csv', header=true, quote='"', escape='"', nullstr='', auto_detect=false,
  columns={'bet_id':'VARCHAR','customer_id':'VARCHAR','state':'VARCHAR','placed_at_utc':'TIMESTAMP','settled_at_utc':'TIMESTAMP','bet_type':'VARCHAR',
           'stake':'DECIMAL(12,2)','is_bonus_bet':'BOOLEAN','payout':'DECIMAL(12,2)','status':'VARCHAR','legs_json':'VARCHAR'});
CREATE TABLE raw.raw_payments AS SELECT * FROM read_csv('mock_data/raw_payments.csv', header=true, nullstr='', auto_detect=false,
  columns={'payment_id':'VARCHAR','customer_id':'VARCHAR','payment_type':'VARCHAR','method':'VARCHAR','amount':'DECIMAL(12,2)','status':'VARCHAR',
           'requested_at':'TIMESTAMP','completed_at':'TIMESTAMP','updated_at':'TIMESTAMP'});
CREATE TABLE raw.raw_payments_batch1 AS SELECT * FROM read_csv('mock_data/raw_payments_batch1.csv', header=true, nullstr='', auto_detect=false,
  columns={'payment_id':'VARCHAR','customer_id':'VARCHAR','payment_type':'VARCHAR','method':'VARCHAR','amount':'DECIMAL(12,2)','status':'VARCHAR',
           'requested_at':'TIMESTAMP','completed_at':'TIMESTAMP','updated_at':'TIMESTAMP'});
CREATE TABLE raw.raw_payments_batch2 AS SELECT * FROM read_csv('mock_data/raw_payments.csv', header=true, nullstr='', auto_detect=false,
  columns={'payment_id':'VARCHAR','customer_id':'VARCHAR','payment_type':'VARCHAR','method':'VARCHAR','amount':'DECIMAL(12,2)','status':'VARCHAR',
           'requested_at':'TIMESTAMP','completed_at':'TIMESTAMP','updated_at':'TIMESTAMP'});
CREATE TABLE raw.raw_kyc_events AS SELECT * FROM read_csv('mock_data/raw_kyc_events.csv', header=true, nullstr='', auto_detect=false,
  columns={'customer_id':'VARCHAR','state':'VARCHAR','event_name':'VARCHAR','event_ts_utc':'TIMESTAMP'});
CREATE TABLE raw.raw_fraud_alerts AS SELECT * FROM read_csv('mock_data/raw_fraud_alerts.csv', header=true, nullstr='', auto_detect=false,
  columns={'alert_id':'VARCHAR','customer_id':'VARCHAR','alert_type':'VARCHAR','severity':'VARCHAR','rule_name':'VARCHAR','created_at_utc':'TIMESTAMP',
           'related_payment_id':'VARCHAR','rule_detail':'VARCHAR','status':'VARCHAR','disposition':'VARCHAR','resolved_at_utc':'TIMESTAMP'});
CREATE TABLE raw.raw_cx_tickets AS SELECT * FROM read_csv('mock_data/raw_cx_tickets.csv', header=true, nullstr='', auto_detect=false,
  columns={'ticket_id':'VARCHAR','customer_id':'VARCHAR','state':'VARCHAR','channel':'VARCHAR','queue':'VARCHAR','contact_reason':'VARCHAR','priority':'VARCHAR',
           'created_at_utc':'TIMESTAMP','first_response_at_utc':'TIMESTAMP','resolved_at_utc':'TIMESTAMP','status':'VARCHAR','csat_score':'INTEGER',
           'reopened_count':'INTEGER','related_bet_id':'VARCHAR','related_payment_id':'VARCHAR','_loaded_at':'TIMESTAMP'});
CREATE TABLE raw.raw_promos AS SELECT * FROM read_csv('mock_data/raw_promos.csv', header=true, quote='"', escape='"', nullstr='', auto_detect=false,
  columns={'promo_id':'VARCHAR','promo_name':'VARCHAR','promo_type':'VARCHAR','eligible_states':'VARCHAR','start_at_utc':'TIMESTAMP','end_at_utc':'TIMESTAMP',
           'token_amount':'DECIMAL(12,2)','max_tokens_per_customer':'INTEGER','min_american_odds':'INTEGER','notes':'VARCHAR'});
CREATE TABLE raw.raw_promo_awards AS SELECT * FROM read_csv('mock_data/raw_promo_awards.csv', header=true, nullstr='', auto_detect=false,
  columns={'award_id':'VARCHAR','promo_id':'VARCHAR','customer_id':'VARCHAR','award_type':'VARCHAR','award_amount':'DECIMAL(12,2)','awarded_at_utc':'TIMESTAMP',
           'expires_at_utc':'TIMESTAMP','status':'VARCHAR','redeemed_bet_id':'VARCHAR','earned_on_bet_id':'VARCHAR','updated_at':'TIMESTAMP'});
CREATE TABLE raw.state_tax_rates AS SELECT * FROM read_csv('mock_data/state_tax_rates.csv', header=true, nullstr='', auto_detect=false,
  columns={'state':'VARCHAR','osb_tax_rate':'DECIMAL(6,4)','promo_deductible_toy':'BOOLEAN','tax_basis':'VARCHAR','rate_note':'VARCHAR'});

SELECT '== ROW COUNTS (compare with section 5 of the Snowflake script) ==' AS check;
SELECT table_name, estimated_size AS row_count FROM duckdb_tables() WHERE schema_name='raw' ORDER BY table_name;

SELECT '== INTEGRITY ==' AS check;
SELECT
 (SELECT count(*) - count(DISTINCT bet_id) FROM raw.raw_bets)                 AS dup_bet_ids,
 (SELECT count(*) - count(DISTINCT payment_id) FROM raw.raw_payments)         AS dup_payment_ids,
 (SELECT count(*) FROM raw.raw_bets b ANTI JOIN raw.raw_customers c USING (customer_id)) AS orphan_bets,
 (SELECT count(*) FROM raw.raw_payments p ANTI JOIN raw.raw_customers c USING (customer_id)) AS orphan_payments,
 (SELECT count(*) FROM raw.raw_bets WHERE json_valid(legs_json) IS NOT TRUE)  AS invalid_json,
 (SELECT count(*) FROM raw.raw_bets WHERE json_array_length(legs_json) = 0)   AS empty_legs_arrays,
 (SELECT count(*) FROM raw.raw_bets WHERE status='settled' AND payout IS NULL) AS settled_null_payout,
 (SELECT count(*) FROM raw.raw_bets WHERE settled_at_utc < placed_at_utc)      AS settled_before_placed,
 (SELECT count(*) FROM raw.raw_bets b JOIN (SELECT customer_id, min(requested_at) fd FROM raw.raw_payments WHERE payment_type='deposit' GROUP BY 1) d USING (customer_id) WHERE b.placed_at_utc < d.fd) AS bets_before_first_deposit,
 (SELECT count(*) FROM raw.raw_bets b ANTI JOIN raw.raw_payments p ON p.customer_id=b.customer_id AND p.payment_type='deposit') AS bettors_without_deposit_rows,
 (SELECT count(*) FROM raw.raw_kyc_events f JOIN raw.raw_kyc_events k ON k.customer_id=f.customer_id AND k.event_name='kyc_passed' WHERE f.event_name='first_deposit' AND f.event_ts_utc < k.event_ts_utc) AS ftd_before_kyc_pass,
 (SELECT count(*) FROM raw.raw_kyc_events f ANTI JOIN raw.raw_kyc_events k ON k.customer_id=f.customer_id AND k.event_name='kyc_passed' WHERE f.event_name='first_deposit') AS ftd_without_kyc_pass,
 (SELECT count(*) FROM raw.raw_bets WHERE placed_at_utc > TIMESTAMP '2026-10-17 04:00:00' OR settled_at_utc > TIMESTAMP '2026-10-17 04:00:00') AS future_rows,
 (SELECT count(*) - count(DISTINCT ticket_id) FROM raw.raw_cx_tickets)         AS cx_dup_rows_intended,
 (SELECT count(DISTINCT lower(trim(channel))) FROM raw.raw_cx_tickets)         AS cx_channels_after_clean,
 (SELECT count(DISTINCT channel) FROM raw.raw_cx_tickets)                      AS cx_channel_raw_variants;

SELECT '== PROFILE: bets ==' AS check;
SELECT bet_type, status, is_bonus_bet, count(*) n, sum(stake) stake, sum(payout) payout FROM raw.raw_bets GROUP BY ALL ORDER BY ALL;
SELECT min(placed_at_utc), max(placed_at_utc), max(settled_at_utc) FROM raw.raw_bets;
SELECT vip_tier, count(*) customers, sum(is_test_account::int) test_accts FROM raw.raw_customers GROUP BY 1 ORDER BY 2 DESC;

-- ============ EXERCISE 1: flatten legs + lost-by-one-leg ============
SELECT '== EX1 flatten legs ==' AS check;
CREATE TABLE int_bet_legs AS
WITH exploded AS (
  SELECT b.bet_id, b.bet_type, unnest(from_json(b.legs_json, '["JSON"]')) AS leg,
         generate_subscripts(from_json(b.legs_json, '["JSON"]'), 1) - 1 AS leg_index
  FROM raw.raw_bets b)
SELECT bet_id, bet_type, leg_index, leg->>'sport' sport, leg->>'event' AS "event", leg->>'market' market, leg->>'selection' selection,
       CAST(leg->>'american_odds' AS INTEGER) american_odds, leg->>'result' leg_result FROM exploded;
SELECT (SELECT count(*) FROM int_bet_legs) AS leg_rows, (SELECT count(DISTINCT bet_id) FROM int_bet_legs) AS bets_with_legs,
       (SELECT count(*) FROM raw.raw_bets) AS bets, '<- 2 bets have [] and vanish without OUTER => TRUE' AS note;
SELECT market, leg_result, count(*) FROM int_bet_legs GROUP BY ALL ORDER BY ALL;
CREATE TABLE fct_bets AS
SELECT b.*, CAST(timezone('America/New_York', timezone('UTC', b.settled_at_utc)) AS DATE) AS settled_date_et,
  CASE WHEN b.status='settled' AND NOT b.is_bonus_bet THEN b.stake ELSE 0 END AS cash_handle,
  CASE WHEN b.status='settled' AND NOT b.is_bonus_bet THEN b.stake - b.payout ELSE 0 END AS cash_ggr,
  CASE WHEN b.status='settled' AND b.is_bonus_bet THEN b.payout ELSE 0 END AS bonus_cost
FROM raw.raw_bets b JOIN raw.raw_customers c USING (customer_id) WHERE NOT c.is_test_account;
SELECT b.bet_type, count(*) AS parlays_lost_by_one_leg, round(avg(p.dec_odds),2) avg_decimal_odds, sum(b.stake) stake
FROM (SELECT l.bet_id, round(exp(sum(ln(CASE WHEN american_odds>0 THEN 1+american_odds/100.0 ELSE 1+100.0/abs(american_odds) END))),4) dec_odds
      FROM int_bet_legs l GROUP BY 1 HAVING sum(CASE WHEN leg_result='lost' THEN 1 ELSE 0 END)=1) p
JOIN fct_bets b USING (bet_id) WHERE b.bet_type IN ('parlay','sgp') AND b.status='settled' GROUP BY 1;

-- ============ EXERCISE 2: SCD2 from v1 -> v2 snapshot, and from vip_tier_history ============
SELECT '== EX2 SCD2 ==' AS check;
-- emulate dbt snapshot (timestamp strategy): v1 rows, closed when v2 has newer updated_at
CREATE TABLE snap_customer_vip AS
SELECT v1.customer_id, v1.vip_tier, v1.updated_at AS dbt_valid_from,
       CASE WHEN v2.updated_at > v1.updated_at THEN v2.updated_at ELSE TIMESTAMP '9999-12-31' END AS dbt_valid_to
FROM raw.raw_customers_v1 v1 JOIN raw.raw_customers_v2 v2 USING (customer_id)
UNION ALL
SELECT v2.customer_id, v2.vip_tier, v2.updated_at, TIMESTAMP '9999-12-31'
FROM raw.raw_customers_v1 v1 JOIN raw.raw_customers_v2 v2 USING (customer_id) WHERE v2.updated_at > v1.updated_at;
SELECT count(*) FILTER (WHERE dbt_valid_to < '9999-12-31') AS customers_changed_between_loads FROM snap_customer_vip;
-- event-sourced SCD2 (full history) with LEAD
CREATE TABLE dim_vip_scd2 AS
WITH ev AS (
  SELECT customer_id, 'bronze' AS vip_tier, signup_ts_utc AS valid_from FROM raw.raw_customers
  UNION ALL SELECT customer_id, to_tier, changed_at_utc FROM raw.raw_vip_tier_history)
SELECT *, coalesce(lead(valid_from) OVER (PARTITION BY customer_id ORDER BY valid_from), TIMESTAMP '9999-12-31') AS valid_to FROM ev;
SELECT 'snapshot misses intermediate tiers for' AS note, count(*) AS customers
FROM (SELECT customer_id FROM raw.raw_vip_tier_history WHERE changed_at_utc >= '2026-10-15' GROUP BY 1 HAVING count(*) >= 2);
SELECT (SELECT count(*) FROM dim_vip_scd2 d JOIN raw.raw_customers c USING (customer_id) WHERE d.valid_to='9999-12-31' AND d.vip_tier <> c.vip_tier) AS history_vs_current_mismatch;
SELECT s.vip_tier AS tier_at_bet, sum(f.cash_handle) handle_at_bet_tier,
       (SELECT sum(f2.cash_handle) FROM fct_bets f2 JOIN raw.raw_customers c USING (customer_id) WHERE c.vip_tier = s.vip_tier) AS handle_if_joined_on_current_tier
FROM fct_bets f JOIN dim_vip_scd2 s ON s.customer_id=f.customer_id AND f.placed_at_utc >= s.valid_from AND f.placed_at_utc < s.valid_to
GROUP BY 1 ORDER BY 2 DESC;

-- ============ EXERCISE 3: incremental MERGE, naive vs lookback ============
SELECT '== EX3 incremental ==' AS check;
CREATE TABLE fct_naive AS SELECT * FROM raw.raw_payments_batch1;
CREATE TABLE fct_lookback AS SELECT * FROM raw.raw_payments_batch1;
CREATE TABLE hw AS SELECT max(updated_at) AS m FROM fct_naive;
MERGE INTO fct_naive t USING (SELECT * FROM raw.raw_payments_batch2 WHERE updated_at >= (SELECT m FROM hw)) s ON t.payment_id = s.payment_id
  WHEN MATCHED THEN UPDATE SET status=s.status, completed_at=s.completed_at, updated_at=s.updated_at WHEN NOT MATCHED THEN INSERT *;
MERGE INTO fct_lookback t USING (SELECT * FROM raw.raw_payments_batch2 WHERE updated_at >= (SELECT m FROM hw) - INTERVAL 7 DAY) s ON t.payment_id = s.payment_id
  WHEN MATCHED THEN UPDATE SET status=s.status, completed_at=s.completed_at, updated_at=s.updated_at WHEN NOT MATCHED THEN INSERT *;
SELECT (SELECT m FROM hw) AS batch1_max_updated_at,
       (SELECT count(*) FROM raw.raw_payments_batch2) AS source_rows,
       (SELECT count(*) FROM fct_naive) AS naive_rows, (SELECT count(*) FROM fct_lookback) AS lookback_rows,
       (SELECT count(*) - count(DISTINCT payment_id) FROM fct_lookback) AS dupes,
       (SELECT count(*) FROM fct_lookback t JOIN raw.raw_payments_batch2 s USING (payment_id) WHERE t.status <> s.status) AS status_mismatch_vs_source,
       (SELECT count(*) FROM raw.raw_payments_batch1 b1 JOIN raw.raw_payments_batch2 b2 USING (payment_id) WHERE b1.status <> b2.status) AS status_changes_in_batch2,
       (SELECT count(*) FROM raw.raw_payments_batch2 WHERE status='chargeback') AS chargebacks_old_requested_new_updated;
SELECT payment_type, method, count(*) attempts, sum((status='completed')::int) completed,
       round(sum((status='completed')::int) / nullif(sum((status IN ('completed','failed'))::int),0), 4) success_rate_resolved,
       sum((status='pending')::int) pending,
       round(median(CASE WHEN payment_type='withdrawal' AND status='completed' THEN date_diff('minute', requested_at, completed_at)/60.0 END), 2) median_hours_to_withdraw
FROM fct_lookback GROUP BY 1,2 ORDER BY 1,2;

-- ============ EXERCISE 4: hold % and NGR by state ============
SELECT '== EX4 hold/NGR by state ==' AS check;
WITH f AS (SELECT * FROM fct_bets WHERE status='settled'),
agg AS (SELECT state, count(*) settled_bets, sum(cash_handle) cash_handle, sum(cash_ggr) cash_ggr, sum(bonus_cost) bonus_cost FROM f GROUP BY state)
SELECT a.state, a.settled_bets, a.cash_handle, a.cash_ggr, round(a.cash_ggr / nullif(a.cash_handle,0), 4) hold_pct, a.bonus_cost,
       a.cash_ggr - a.bonus_cost ngr, t.osb_tax_rate, t.tax_basis,
       round(greatest(CASE WHEN t.promo_deductible_toy THEN a.cash_ggr - a.bonus_cost ELSE a.cash_ggr END, 0) * t.osb_tax_rate, 2) est_tax_course_formula
FROM agg a LEFT JOIN raw.state_tax_rates t USING (state) ORDER BY a.cash_handle DESC;
SELECT round(sum(cash_ggr)/sum(cash_handle),4) AS overall_hold, sum(cash_handle) handle, sum(bonus_cost) bonus_cost,
       (SELECT sum(stake - payout) FROM raw.raw_bets b JOIN raw.raw_customers c USING (customer_id) WHERE c.is_test_account AND b.status='settled' AND NOT b.is_bonus_bet) AS test_acct_ggr_excluded
FROM fct_bets;
SELECT bet_type, round(sum(cash_ggr)/nullif(sum(cash_handle),0),4) AS hold_pct FROM fct_bets GROUP BY 1 ORDER BY 1;

-- ============ EXERCISE 5: pending withdrawals queue ============
SELECT '== EX5 pending withdrawals (age vs dataset as-of 2026-10-17 04:00 UTC) ==' AS check;
SELECT p.payment_id, p.customer_id, c.state, c.vip_tier, p.method, p.amount, p.requested_at,
       round(date_diff('second', p.requested_at, TIMESTAMP '2026-10-17 04:00:00')/3600.0, 1) AS hours_pending
FROM raw.raw_payments p JOIN raw.raw_customers c USING (customer_id)

WHERE p.payment_type='withdrawal' AND p.status='pending' AND (date_diff('second', p.requested_at, TIMESTAMP '2026-10-17 04:00:00')/3600.0 > 24 OR c.vip_tier IN ('gold','platinum')) ORDER BY hours_pending DESC;
SELECT count(*) AS all_pending_withdrawals FROM raw.raw_payments WHERE payment_type='withdrawal' AND status='pending';

-- ============ EXERCISE 6: KYC funnel in ET ============
SELECT '== EX6 KYC funnel ==' AS check;
CREATE TABLE fct_kyc_funnel AS
WITH per AS (
  SELECT customer_id, state,
    min(CASE WHEN event_name='registered' THEN event_ts_utc END) registered_at,
    min(CASE WHEN event_name='kyc_submitted' THEN event_ts_utc END) first_submit_at,
    min(CASE WHEN event_name='kyc_passed' THEN event_ts_utc END) kyc_passed_at,
    sum(CASE WHEN event_name='kyc_failed' THEN 1 ELSE 0 END) kyc_fail_count,
    min(CASE WHEN event_name='first_deposit' THEN event_ts_utc END) first_deposit_at
  FROM raw.raw_kyc_events GROUP BY 1,2)
SELECT *, CAST(timezone('America/New_York', timezone('UTC', registered_at)) AS DATE) registered_date_et, CAST(registered_at AS DATE) registered_date_utc,
  date_diff('minute', registered_at, kyc_passed_at) minutes_to_kyc_pass,
  date_diff('minute', first_submit_at, kyc_passed_at) <= 5 AS auto_passed_proxy,
  coalesce(first_deposit_at <= registered_at + INTERVAL 24 HOUR, false) ftd_within_24h
FROM per;
SELECT state, count(*) registered, count(first_submit_at) submitted, count(kyc_passed_at) passed, count(first_deposit_at) ftd,
       sum(ftd_within_24h::int) ftd_24h, round(count(kyc_passed_at)/count(first_submit_at)::double, 3) pass_rate,
       median(minutes_to_kyc_pass) med_min_to_pass, round(avg(auto_passed_proxy::int),3) auto_pass_share
FROM fct_kyc_funnel GROUP BY 1 ORDER BY registered DESC;
SELECT count(*) FILTER (WHERE registered_date_et <> registered_date_utc) AS registrations_on_different_day_in_et, count(*) total FROM fct_kyc_funnel;

-- ============ EXERCISE 7: metric defined once (semantic-view equivalent) ============
SELECT '== EX7 metrics by vip tier (current) ==' AS check;
SELECT c.vip_tier, sum(f.cash_handle) total_handle, sum(f.cash_ggr) total_ggr, round(sum(f.cash_ggr)/nullif(sum(f.cash_handle),0),4) hold_pct,
       sum(f.cash_ggr) - sum(f.bonus_cost) ngr
FROM fct_bets f JOIN raw.raw_customers c USING (customer_id) GROUP BY 1 ORDER BY 2 DESC;

-- ============ Extra tables: CX, fraud, promos ============
SELECT '== CX dedupe + SLA ==' AS check;
WITH d AS (SELECT * FROM raw.raw_cx_tickets QUALIFY row_number() OVER (PARTITION BY ticket_id ORDER BY _loaded_at DESC) = 1)
SELECT lower(trim(channel)) channel, queue, count(*) tickets, median(date_diff('minute', created_at_utc, first_response_at_utc)) med_frt_min,
       round(avg(CASE WHEN date_diff('minute', created_at_utc, first_response_at_utc) <= 15 THEN 1.0 ELSE 0.0 END),3) frt_sla_15m,
       count(*) FILTER (WHERE status <> 'solved') backlog
FROM d GROUP BY 1,2 ORDER BY 1,2;
SELECT contact_reason, count(DISTINCT ticket_id) FROM raw.raw_cx_tickets GROUP BY 1 ORDER BY 2 DESC;
SELECT '== fraud ==' AS check;
SELECT alert_type, count(*) alerts, count(*) FILTER (WHERE disposition='confirmed') confirmed, count(*) FILTER (WHERE disposition='false_positive') false_pos, count(*) FILTER (WHERE status='open') open_
FROM raw.raw_fraud_alerts GROUP BY 1 ORDER BY 2 DESC;
SELECT '== promos ==' AS check;
SELECT promo_id, award_type, status, count(*) n, sum(award_amount) amt FROM raw.raw_promo_awards GROUP BY ALL ORDER BY ALL;
SELECT (SELECT count(*) FROM raw.raw_bets WHERE is_bonus_bet) bonus_bets,
       (SELECT count(*) FROM raw.raw_promo_awards WHERE redeemed_bet_id IS NOT NULL) redeemed_awards,
       (SELECT count(*) FROM raw.raw_promo_awards a ANTI JOIN raw.raw_bets b ON b.bet_id = a.redeemed_bet_id WHERE a.redeemed_bet_id IS NOT NULL) orphan_redemptions;
