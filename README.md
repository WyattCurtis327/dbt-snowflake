# Sportsbook tutorial

Medallion layout: **landing → bronze → silver → gold → semantic**.

```
sportsbook/     dbt project
  models/landing/   sources (PUT/COPY or dbt seed) — not bronze
  models/bronze/    brz_* views
  models/silver/    slv_* joins / business rules
  models/gold/      fct_ / mart_ / dt_ / sem_*
docs/course.md  living crash course (keep edits here, not in Downloads)
snowflake/      setup, load (landing + dbt), teardown
data/           CSVs for Snowflake PUT/COPY
STUDY.md        this week's plan
```

Local dbt (DuckDB):

```powershell
cd sportsbook
$env:DBT_PROFILES_DIR = "."
dbt build
```

Or `sportsbook/run_all.sh` (Day 1 seed → snapshot → build, then Day 2).

Snowflake trial — full project cycle from the repo root:

```powershell
copy .env.example .env
.\.venv\Scripts\python.exe snowflake\run.py setup
.\.venv\Scripts\python.exe snowflake\run.py load
# inspect FBG_PREP.LANDING / BRONZE / GOLD in Snowsight
.\.venv\Scripts\python.exe snowflake\run.py teardown   # only when you want a clean slate
```

`setup` creates the warehouse, `FBG_PREP`, schemas, and roles. `load` PUTs/COPYs CSVs into **LANDING**, then runs `dbt snapshot` + `dbt build` so `brz_` / `slv_` / `fct_` / `mart_` / `sem_` exist in Snowflake. `teardown` drops the database and roles. Shortcut: `python snowflake/run.py all` (setup + load, leaves objects built).

Details: [snowflake/README.md](snowflake/README.md).

dbt platform (Cloud): do not use Partner Connect. Connect this GitHub repo with subdirectory `sportsbook` and warehouse `FBG_PREP` / `OPS_XS_WH`. Steps: [docs/dbt-cloud.md](docs/dbt-cloud.md).
