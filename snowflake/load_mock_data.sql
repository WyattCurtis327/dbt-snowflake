-- =====================================================================================
-- FBG prep: load the MOCK sportsbook dataset into your Snowflake trial
-- [Snowflake-only, NOT executed] Written against Snowflake docs; there is no Snowflake
-- account on the box. The same CSVs, column types and checks WERE executed in DuckDB
-- (data/validate_duckdb.sql). Tutorial dbt models use the smaller sportsbook/seeds set.
--
-- 100% FAKE DATA: synthetic customers C0001-C0500, simulated games/lines/scores (real team
-- abbreviations only), Aug 1 - Oct 16 2026, "as of" 2026-10-17 04:00 UTC. All timestamps UTC.
--
-- PREREQ: snowflake/day1_setup.sql already run (OPS_XS_WH, FBG_PREP.LANDING/BRONZE/SILVER/GOLD, role TRANSFORMER).
--
-- ---------------- HOW TO GET THE FILES ONTO THE STAGE (pick one) ----------------
-- 1) Run SECTIONS 0-2 below first (they create the stage).
-- 2a) Snowsight (easiest): top-right role picker -> TRANSFORMER (or ACCOUNTADMIN).
--     Left nav: Ingestion > Add Data > "Load files into a Stage".
--     Drag in all 12 CSVs from data/, pick database FBG_PREP,
--     schema LANDING, stage MOCK_STAGE, leave Path empty, click Upload.
--     (Alt route: Catalog > Database Explorer > FBG_PREP > LANDING > Stages > MOCK_STAGE > "+ Files".)
-- 2b) From this repo:  python snowflake/run.py load
--     That PUTs data/*.csv to @FBG_PREP.LANDING.MOCK_STAGE and runs this script.
-- 3) Back in the worksheet run SECTION 3 (LIST) to confirm 12 files, then SECTIONS 4-6.
-- =====================================================================================

-- ---------- 0. Fix-up grant: TRANSFORMER needs these to create a stage / file format ----------
-- (Day-1's CREATE FILE FORMAT line ran as TRANSFORMER and probably failed with
--  "insufficient privileges"; this grant fixes that.) SYSADMIN owns the schema, so it can grant.
USE ROLE SYSADMIN;
GRANT CREATE STAGE, CREATE FILE FORMAT ON SCHEMA FBG_PREP.LANDING TO ROLE TRANSFORMER;

USE ROLE TRANSFORMER;
USE WAREHOUSE OPS_XS_WH;
USE SCHEMA FBG_PREP.LANDING;

-- ---------- 1. File format + internal stage ----------
CREATE FILE FORMAT IF NOT EXISTS FBG_PREP.LANDING.MOCK_CSV
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_DELIMITER = ','
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'      -- legs_json is quoted, inner quotes doubled ("")
  NULL_IF = ('')                          -- empty field = NULL (settled_at, payout on open bets, ...)
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = FALSE                      -- keep the deliberately messy CX channel values (' chat', 'EMAIL ')
  TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  COMPRESSION = AUTO;                     -- plain .csv from Snowsight or .csv.gz from PUT

-- IF NOT EXISTS on purpose: CREATE OR REPLACE STAGE would delete files you already uploaded.
CREATE STAGE IF NOT EXISTS FBG_PREP.LANDING.MOCK_STAGE
  FILE_FORMAT = FBG_PREP.LANDING.MOCK_CSV
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'FBG prep: mock sportsbook CSVs';

-- ---------- 2. Landing tables (as-landed; dbt brz_* does the casting/cleanup) ----------
-- CREATE OR REPLACE makes the whole script re-runnable. RAW_BETS matches the Day-1 DDL exactly.
CREATE OR REPLACE TABLE RAW_CUSTOMERS (
  customer_id STRING, state STRING, signup_ts_utc TIMESTAMP_NTZ, vip_tier STRING,
  is_test_account BOOLEAN, updated_at TIMESTAMP_NTZ);                       -- current state, tier overwritten (Ex 2)

CREATE OR REPLACE TABLE RAW_VIP_TIER_HISTORY (
  vip_change_id STRING, customer_id STRING, from_tier STRING, to_tier STRING,
  changed_at_utc TIMESTAMP_NTZ, change_reason STRING);                      -- event log -> SCD2 with LEAD (Ex 2 alt)

CREATE OR REPLACE TABLE RAW_BETS (
  bet_id         STRING,
  customer_id    STRING,
  state          STRING,
  placed_at_utc  TIMESTAMP_NTZ,
  settled_at_utc TIMESTAMP_NTZ,
  bet_type       STRING,          -- single | parlay | sgp
  stake          NUMBER(12,2),
  is_bonus_bet   BOOLEAN,
  payout         NUMBER(12,2),    -- cash returned; bonus bets = winnings only; NULL while open
  status         STRING,          -- settled | void | open
  legs_json      STRING           -- slv_bet_legs does PARSE_JSON + LATERAL FLATTEN on this (Ex 1)
);

CREATE OR REPLACE TABLE RAW_PAYMENTS (
  payment_id STRING, customer_id STRING, payment_type STRING, method STRING, amount NUMBER(12,2),
  status STRING,                  -- pending | completed | failed | cancelled | chargeback
  requested_at TIMESTAMP_NTZ, completed_at TIMESTAMP_NTZ, updated_at TIMESTAMP_NTZ);   -- Ex 3, Ex 5

CREATE OR REPLACE TABLE RAW_KYC_EVENTS (
  customer_id STRING, state STRING,
  event_name STRING,              -- registered | kyc_submitted | kyc_failed | kyc_passed | first_deposit
  event_ts_utc TIMESTAMP_NTZ);                                               -- Ex 6

CREATE OR REPLACE TABLE RAW_CX_TICKETS (
  ticket_id STRING, customer_id STRING, state STRING, channel STRING, queue STRING, contact_reason STRING,
  priority STRING, created_at_utc TIMESTAMP_NTZ, first_response_at_utc TIMESTAMP_NTZ, resolved_at_utc TIMESTAMP_NTZ,
  status STRING,                  -- new | open | pending | solved
  csat_score NUMBER(1,0), reopened_count NUMBER(3,0), related_bet_id STRING, related_payment_id STRING,
  _loaded_at TIMESTAMP_NTZ);      -- NOT unique on ticket_id on purpose: reload duplicates -> QUALIFY dedupe

CREATE OR REPLACE TABLE RAW_FRAUD_ALERTS (
  alert_id STRING, customer_id STRING, alert_type STRING, severity STRING, rule_name STRING,
  created_at_utc TIMESTAMP_NTZ, related_payment_id STRING, rule_detail STRING,
  status STRING, disposition STRING, resolved_at_utc TIMESTAMP_NTZ);         -- includes alert_type='test' rows

CREATE OR REPLACE TABLE RAW_PROMOS (
  promo_id STRING, promo_name STRING, promo_type STRING, eligible_states STRING,   -- 'ALL' or 'NJ|PA|MI|IL'
  start_at_utc TIMESTAMP_NTZ, end_at_utc TIMESTAMP_NTZ, token_amount NUMBER(12,2),
  max_tokens_per_customer NUMBER(3,0), min_american_odds NUMBER(6,0), notes STRING);

CREATE OR REPLACE TABLE RAW_PROMO_AWARDS (
  award_id STRING, promo_id STRING, customer_id STRING, award_type STRING,    -- bonus_bet | fancash
  award_amount NUMBER(12,2), awarded_at_utc TIMESTAMP_NTZ, expires_at_utc TIMESTAMP_NTZ,
  status STRING,                  -- active | redeemed | expired | revoked | credited
  redeemed_bet_id STRING, earned_on_bet_id STRING, updated_at TIMESTAMP_NTZ);

CREATE OR REPLACE TABLE STATE_TAX_RATES (
  state STRING, osb_tax_rate NUMBER(6,4), promo_deductible_toy BOOLEAN,
  tax_basis STRING,               -- ggr | handle (TN taxes handle)
  rate_note STRING);              -- rates are approximate/simplified: verify before quoting

-- ---------- 3. Confirm the upload ----------
LIST @FBG_PREP.LANDING.MOCK_STAGE;     -- expect 12 files

-- ---------- 4. COPY INTO (current-state files) ----------
-- PATTERN matches 'x.csv' or 'x.csv.gz', with or without a folder path in the stage.
COPY INTO RAW_CUSTOMERS        FROM @MOCK_STAGE PATTERN = '(.*/)?raw_customers[.]csv([.]gz)?'        FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_VIP_TIER_HISTORY FROM @MOCK_STAGE PATTERN = '(.*/)?raw_vip_tier_history[.]csv([.]gz)?' FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_BETS             FROM @MOCK_STAGE PATTERN = '(.*/)?raw_bets[.]csv([.]gz)?'             FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_PAYMENTS         FROM @MOCK_STAGE PATTERN = '(.*/)?raw_payments[.]csv([.]gz)?'         FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_KYC_EVENTS       FROM @MOCK_STAGE PATTERN = '(.*/)?raw_kyc_events[.]csv([.]gz)?'       FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_CX_TICKETS       FROM @MOCK_STAGE PATTERN = '(.*/)?raw_cx_tickets[.]csv([.]gz)?'       FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_FRAUD_ALERTS     FROM @MOCK_STAGE PATTERN = '(.*/)?raw_fraud_alerts[.]csv([.]gz)?'     FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_PROMOS           FROM @MOCK_STAGE PATTERN = '(.*/)?raw_promos[.]csv([.]gz)?'           FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO RAW_PROMO_AWARDS     FROM @MOCK_STAGE PATTERN = '(.*/)?raw_promo_awards[.]csv([.]gz)?'     FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
COPY INTO STATE_TAX_RATES      FROM @MOCK_STAGE PATTERN = '(.*/)?state_tax_rates[.]csv([.]gz)?'      FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') ON_ERROR = 'ABORT_STATEMENT';
-- Dry run alternative for any table: add VALIDATION_MODE = RETURN_ERRORS to a COPY (loads nothing).
-- Re-running a COPY on an unchanged file loads 0 rows (64-day load metadata); add FORCE = TRUE to reload.

-- ---------- 5. Row-count + sanity checks (every row should say OK) ----------
SELECT t, actual, expected, IFF(actual = expected, 'OK', '<<< CHECK') AS result FROM (
            SELECT 'RAW_CUSTOMERS'        t, COUNT(*) actual,   500 expected FROM RAW_CUSTOMERS
  UNION ALL SELECT 'RAW_VIP_TIER_HISTORY',   COUNT(*),            219          FROM RAW_VIP_TIER_HISTORY
  UNION ALL SELECT 'RAW_BETS',               COUNT(*),          11641          FROM RAW_BETS
  UNION ALL SELECT 'RAW_PAYMENTS',           COUNT(*),           3140          FROM RAW_PAYMENTS
  UNION ALL SELECT 'RAW_KYC_EVENTS',         COUNT(*),           1944          FROM RAW_KYC_EVENTS
  UNION ALL SELECT 'RAW_CX_TICKETS',         COUNT(*),           1043          FROM RAW_CX_TICKETS
  UNION ALL SELECT 'RAW_CX_TICKETS distinct ticket_id', COUNT(DISTINCT ticket_id), 973 FROM RAW_CX_TICKETS
  UNION ALL SELECT 'RAW_FRAUD_ALERTS',       COUNT(*),             82          FROM RAW_FRAUD_ALERTS
  UNION ALL SELECT 'RAW_PROMOS',             COUNT(*),              6          FROM RAW_PROMOS
  UNION ALL SELECT 'RAW_PROMO_AWARDS',       COUNT(*),           1913          FROM RAW_PROMO_AWARDS
  UNION ALL SELECT 'STATE_TAX_RATES',        COUNT(*),             15          FROM STATE_TAX_RATES
  UNION ALL SELECT 'bet legs via FLATTEN',   COUNT(*),          22722
            FROM RAW_BETS b, LATERAL FLATTEN(input => PARSE_JSON(b.legs_json))
  UNION ALL SELECT 'bets with [] legs (dropped w/o OUTER=>TRUE)', COUNT(*), 2
            FROM RAW_BETS WHERE ARRAY_SIZE(PARSE_JSON(legs_json)) = 0
  UNION ALL SELECT 'duplicate bet_id',       COUNT(*) - COUNT(DISTINCT bet_id), 0 FROM RAW_BETS
  UNION ALL SELECT 'duplicate payment_id',   COUNT(*) - COUNT(DISTINCT payment_id), 0 FROM RAW_PAYMENTS
  UNION ALL SELECT 'pending withdrawals',    COUNT(*),             11 FROM RAW_PAYMENTS WHERE payment_type = 'withdrawal' AND status = 'pending'
) ORDER BY t;

-- Quick taste of each exercise (hold % by state should show NY ~7.3% on $209k cash handle):
SELECT b.state,
       SUM(IFF(b.status = 'settled' AND NOT b.is_bonus_bet, b.stake, 0))            AS cash_handle,
       SUM(IFF(b.status = 'settled' AND NOT b.is_bonus_bet, b.stake - b.payout, 0)) AS cash_ggr,
       DIV0NULL(cash_ggr, cash_handle)                                               AS hold_pct
FROM RAW_BETS b JOIN RAW_CUSTOMERS c USING (customer_id)
WHERE NOT c.is_test_account
GROUP BY 1 ORDER BY cash_handle DESC;

-- Ex 5 read-time aging. NOTE: QUALIFY needs a window function in Snowflake, so filter with WHERE.
-- Data is frozen at 2026-10-17 04:00 UTC; use that instead of CURRENT_TIMESTAMP() or everything looks days old.
SELECT p.payment_id, p.customer_id, c.state, c.vip_tier, p.method, p.amount, p.requested_at,
       DATEDIFF('second', p.requested_at, '2026-10-17 04:00:00'::TIMESTAMP_NTZ) / 3600.0 AS hours_pending
FROM RAW_PAYMENTS p JOIN RAW_CUSTOMERS c USING (customer_id)
WHERE p.payment_type = 'withdrawal' AND p.status = 'pending'
  AND (hours_pending > 24 OR c.vip_tier IN ('gold', 'platinum'))
ORDER BY hours_pending DESC;    -- expect 7 rows (4 gold/platinum ACH withdrawals of $4k-$8.8k + 3 small ones aged 47-67h)

-- ---------- 6. REPLAY for Exercises 2 (snapshot) and 3 (incremental late-arriving bug) ----------
-- Do this when you get to Tue's block. Day 1 = the 10/15 00:00 UTC extract; Day 2 = current files.
-- TRUNCATE clears COPY load metadata, FORCE=TRUE makes it explicit.
-- (a) Day-1 state:
-- TRUNCATE TABLE RAW_CUSTOMERS;  COPY INTO RAW_CUSTOMERS FROM @MOCK_STAGE PATTERN = '(.*/)?raw_customers_v1[.]csv([.]gz)?'   FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') FORCE = TRUE;
-- TRUNCATE TABLE RAW_PAYMENTS;   COPY INTO RAW_PAYMENTS  FROM @MOCK_STAGE PATTERN = '(.*/)?raw_payments_batch1[.]csv([.]gz)?' FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') FORCE = TRUE;
--   expect 500 customers, 2974 payments  -> then: dbt snapshot && dbt build --exclude fct_bets_with_vip_tier
-- (b) Day-2 state:
-- TRUNCATE TABLE RAW_CUSTOMERS;  COPY INTO RAW_CUSTOMERS FROM @MOCK_STAGE PATTERN = '(.*/)?raw_customers[.]csv([.]gz)?'  FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') FORCE = TRUE;
-- TRUNCATE TABLE RAW_PAYMENTS;   COPY INTO RAW_PAYMENTS  FROM @MOCK_STAGE PATTERN = '(.*/)?raw_payments[.]csv([.]gz)?'   FILE_FORMAT = (FORMAT_NAME = 'FBG_PREP.LANDING.MOCK_CSV') FORCE = TRUE;
--   expect 500 / 3140 -> then: dbt snapshot && dbt build
-- What you should see (verified on dbt-duckdb):
--   * snapshot: 26 customers get a 2nd row; 2 customers changed tier TWICE between loads and the snapshot
--     only shows the final tier (RAW_VIP_TIER_HISTORY has both changes: the "snapshot frequency" talking point)
--   * incremental WITHOUT lookback: 3125 rows, 15 late-arriving deposits silently missing; WITH 7-day lookback: 3140
--   * 8 old card deposits flip completed -> chargeback with a NEW updated_at (why you filter on updated_at, not requested_at)

-- ---------- 7. Point the toy dbt project at these tables ----------
-- models/landing/_sources.yml already uses source('landing') -> FBG_PREP.LANDING.
-- Table names match (raw_bets, raw_customers, raw_payments, raw_kyc_events, state_tax_rates).
-- `python snowflake/run.py load` COPYs here then runs dbt snapshot + build (seeds excluded).

-- Start over from scratch: python snowflake/run.py teardown
