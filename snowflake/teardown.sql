-- Wipe the FBG prep trial objects so day1_setup.sql can run clean.
-- Run from this repo:  python snowflake/run.py teardown
--
-- Drops the database (LANDING/BRONZE/SILVER/GOLD and all dbt objects), the warehouse,
-- the resource monitor, and the two roles. Requires ACCOUNTADMIN.

USE ROLE ACCOUNTADMIN;

SHOW USERS;
SET my_user = (
  SELECT "name"
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
  WHERE LOWER("login_name") = LOWER(CURRENT_USER())
     OR LOWER("name") = LOWER(CURRENT_USER())
  LIMIT 1
);

-- REVOKE FROM USER can 002043 on this trial; DROP ROLE still runs below.
REVOKE ROLE TRANSFORMER FROM ROLE SYSADMIN;
REVOKE ROLE OPS_ANALYST FROM ROLE SYSADMIN;

DROP DATABASE IF EXISTS FBG_PREP;
DROP WAREHOUSE IF EXISTS OPS_XS_WH;
DROP RESOURCE MONITOR IF EXISTS FBG_PREP_RM;
DROP ROLE IF EXISTS OPS_ANALYST;
DROP ROLE IF EXISTS TRANSFORMER;
