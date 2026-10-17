-- =====================================================================
-- Snowflake trial, Day 1 (Sat 10/17) setup worksheet  -- FBG interview prep
-- Paste into a Snowsight SQL worksheet and run top to bottom (Ctrl/Cmd+Shift+Enter
-- runs all, or run block by block to narrate each step aloud).
-- [Snowflake-only, NOT executed]: written against Snowflake docs; there is no
-- Snowflake account on the box. Every object name is new, so it's safe on a fresh trial.
-- Teardown (start over): python snowflake/run.py teardown
-- =====================================================================

-- ---------- 0. Who am I? (trial user starts as ACCOUNTADMIN) ----------
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT(), CURRENT_REGION();
-- CURRENT_USER() on this trial is wyatt.curtis; the user object is the email login.
SHOW USERS;
SET my_user = (
  SELECT "name"
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
  WHERE LOWER("login_name") = LOWER(CURRENT_USER())
     OR LOWER("name") = LOWER(CURRENT_USER())
  LIMIT 1
);
SELECT $my_user AS grant_target_user;

-- ---------- 1. Compute: one XS warehouse, cheap by default ----------
-- SYSADMIN should own warehouses and databases (not ACCOUNTADMIN).
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS OPS_XS_WH
  WAREHOUSE_SIZE      = 'XSMALL'   -- 1 credit/hr, billed per second, 60s minimum per resume
  AUTO_SUSPEND        = 60         -- seconds idle before suspend (trade-off: local disk cache is lost)
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'FBG prep: ops analytics XS warehouse';

-- ---------- 2. Storage: database + medallion schemas ----------
-- Landing is the first stop after PUT/COPY. It is NOT bronze.
CREATE DATABASE IF NOT EXISTS FBG_PREP COMMENT = 'FBG prep sandbox';
CREATE SCHEMA IF NOT EXISTS FBG_PREP.LANDING;  -- PUT/COPY as-landed (sources)
CREATE SCHEMA IF NOT EXISTS FBG_PREP.BRONZE;   -- dbt brz_* views: rename/cast/dedupe
CREATE SCHEMA IF NOT EXISTS FBG_PREP.SILVER;   -- dbt slv_* joins + business rules
CREATE SCHEMA IF NOT EXISTS FBG_PREP.GOLD;     -- dbt fct_/mart_/dt_/sem_* certified metrics

-- ---------- 3. Roles: functional roles in the hierarchy ----------
-- USERADMIN creates roles; roles roll up to SYSADMIN so admins can see what they build.
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS TRANSFORMER COMMENT = 'dbt build role: owns what dbt creates';
CREATE ROLE IF NOT EXISTS OPS_ANALYST COMMENT = 'Read-only consumer of gold marts (Sigma/Tableau)';
GRANT ROLE TRANSFORMER TO ROLE SYSADMIN;
GRANT ROLE OPS_ANALYST TO ROLE SYSADMIN;

-- ---------- 4. Privileges (SECURITYADMIN has MANAGE GRANTS, needed for future grants) ----------
USE ROLE SECURITYADMIN;
-- GRANT ROLE ... TO USER is already true on this trial (CURRENT_AVAILABLE_ROLES
-- lists TRANSFORMER and OPS_ANALYST). Re-running GRANT TO USER returns 002043.

-- TRANSFORMER: read landing, build bronze / silver / gold
GRANT USAGE, OPERATE ON WAREHOUSE OPS_XS_WH TO ROLE TRANSFORMER;
GRANT USAGE, CREATE SCHEMA ON DATABASE FBG_PREP TO ROLE TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW, CREATE STAGE, CREATE FILE FORMAT
  ON SCHEMA FBG_PREP.LANDING TO ROLE TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA FBG_PREP.BRONZE TO ROLE TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA FBG_PREP.SILVER TO ROLE TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA FBG_PREP.GOLD   TO ROLE TRANSFORMER;
GRANT CREATE DYNAMIC TABLE ON SCHEMA FBG_PREP.GOLD TO ROLE TRANSFORMER;  -- Exercise 5
GRANT SELECT ON FUTURE TABLES IN SCHEMA FBG_PREP.LANDING TO ROLE TRANSFORMER;

-- OPS_ANALYST: gold only, read-only, automatic for every future dbt model
GRANT USAGE ON WAREHOUSE OPS_XS_WH TO ROLE OPS_ANALYST;
GRANT USAGE ON DATABASE FBG_PREP TO ROLE OPS_ANALYST;
GRANT USAGE ON SCHEMA FBG_PREP.GOLD TO ROLE OPS_ANALYST;
GRANT SELECT ON FUTURE TABLES         IN SCHEMA FBG_PREP.GOLD TO ROLE OPS_ANALYST;
GRANT SELECT ON FUTURE VIEWS          IN SCHEMA FBG_PREP.GOLD TO ROLE OPS_ANALYST;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA FBG_PREP.GOLD TO ROLE OPS_ANALYST;
-- Talking point: schema-level future grants take precedence over database-level ones.

SHOW GRANTS TO ROLE OPS_ANALYST;
SHOW FUTURE GRANTS IN SCHEMA FBG_PREP.GOLD;

-- ---------- 5. Cost guardrail: resource monitor (ACCOUNTADMIN only) ----------
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS FBG_PREP_RM
  WITH CREDIT_QUOTA = 20 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE OPS_XS_WH SET RESOURCE_MONITOR = FBG_PREP_RM;

-- ---------- 6. Prove the RBAC works ----------
USE ROLE TRANSFORMER;
USE WAREHOUSE OPS_XS_WH;
CREATE OR REPLACE TABLE FBG_PREP.GOLD.RBAC_SMOKE AS SELECT 1 AS ok, CURRENT_ROLE() AS built_by;

USE ROLE OPS_ANALYST;
SELECT * FROM FBG_PREP.GOLD.RBAC_SMOKE;              -- works: future grant fired on create
-- SELECT * FROM FBG_PREP.LANDING.<any table>;       -- would fail: no access to landing (expected)
-- SELECT * FROM FBG_PREP.BRONZE.<any table>;        -- would fail: no access to bronze (expected)

-- ---------- 7. Result cache demo (15 min block) ----------
USE ROLE TRANSFORMER;
USE WAREHOUSE OPS_XS_WH;
USE DATABASE FBG_PREP;                               -- INFORMATION_SCHEMA functions need a database in context
ALTER SESSION SET USE_CACHED_RESULT = TRUE;           -- default, set explicitly for the demo

-- Run this exact query TWICE. Snowflake's shared sample DB is usually present on trials;
-- if not, Snowsight > Data > Databases should list SNOWFLAKE_SAMPLE_DATA to add.
SELECT l_returnflag, l_linestatus,
       SUM(l_quantity) AS qty, SUM(l_extendedprice) AS gross, COUNT(*) AS lines
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
GROUP BY 1, 2 ORDER BY 1, 2;

-- Compare the two runs: the second should show ~0 bytes scanned.
-- In Query Profile (Monitoring > Query History > click the query) it appears as "QUERY RESULT REUSE".
SELECT query_id, LEFT(query_text, 60) AS q, warehouse_name,
       total_elapsed_time AS ms, bytes_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
WHERE query_text ILIKE '%TPCH_SF1.LINEITEM%' AND query_text NOT ILIKE '%QUERY_HISTORY%'
ORDER BY start_time DESC LIMIT 5;

-- Now turn the result cache off and rerun once: it scans again (warehouse local-disk cache may still help).
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
-- (rerun the LINEITEM query, then the history query)
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- ---------- 8. Head start for Monday: landing table for raw_bets.csv ----------
-- Snowsight > Data > Add Data > Load data into a Table can target this table.
-- Alternative: `dbt seed` from the toy project loads all 5 CSVs in one command.
USE ROLE TRANSFORMER;
CREATE TABLE IF NOT EXISTS FBG_PREP.LANDING.RAW_BETS (
  bet_id         STRING,
  customer_id    STRING,
  state          STRING,
  placed_at_utc  TIMESTAMP_NTZ,
  settled_at_utc TIMESTAMP_NTZ,
  bet_type       STRING,
  stake          NUMBER(12,2),
  is_bonus_bet   BOOLEAN,
  payout         NUMBER(12,2),
  status         STRING,
  legs_json      STRING          -- slv_bet_legs does PARSE_JSON + LATERAL FLATTEN on this
);
CREATE FILE FORMAT IF NOT EXISTS FBG_PREP.LANDING.CSV_HEADER
  TYPE = CSV SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"' NULL_IF = ('');

-- ---------- 9. Say it aloud (the Day 1 "output") ----------
-- * Warehouse = compute only, sized XS..6XL, each size doubles credits/hr, per-second billing, 60s min.
-- * AUTO_SUSPEND trades idle cost against losing the local disk cache.
-- * Result cache: identical query + unchanged data = free for 24h, served by cloud services, no warehouse.
-- * RBAC: privileges -> roles -> users; SYSADMIN owns infra; the creating role owns objects,
--   so dbt's role (TRANSFORMER) owns what it builds; future grants make new models readable.
-- * Databricks map: Unity Catalog grants -> roles + future grants; SQL warehouse -> virtual warehouse.
-- * Medallion: LANDING (PUT/COPY) -> BRONZE (brz_) -> SILVER (slv_) -> GOLD (fct_/mart_/sem_).
--   Analysts read GOLD only. Landing is not bronze.
