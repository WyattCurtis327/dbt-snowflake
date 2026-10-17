#!/usr/bin/env bash
# Reproduce every exercise locally on DuckDB (Snowflake-only branches are compiled out).
set -euo pipefail
cd "$(dirname "$0")"
source ../.venv/bin/activate          # pip install dbt-duckdb
export DBT_PROFILES_DIR=.
rm -f sportsbook.duckdb
# --- Day 1 load ---
cp seed_versions/raw_payments_batch1.csv seeds/raw_payments.csv
cp seed_versions/raw_customers_v1.csv   seeds/raw_customers.csv
dbt seed && dbt snapshot && dbt build --exclude fct_bets_with_vip_tier
# --- Day 2 load: payment status updates + late-arriving P10, VIP tier changes for C1/C3 ---
cp seed_versions/raw_payments_batch2.csv seeds/raw_payments.csv
cp seed_versions/raw_customers_v2.csv   seeds/raw_customers.csv
dbt seed && dbt snapshot && dbt build
