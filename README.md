# Sportsbook — Snowflake + dbt

Medallion sportsbook project: **landing → bronze (`brz_`) → silver (`slv_`) → gold (`fct_` / `mart_` / `dt_`) → semantic (`sem_`)**.

Runs two ways:

| Target | Warehouse | How landing is loaded | When to use |
|---|---|---|---|
| `dev` (default) | DuckDB (`sportsbook/sportsbook.duckdb`) | `dbt seed` | Local tutorial, no Snowflake |
| `snowflake` | Trial `FBG_PREP` | PUT/COPY into `LANDING` | Cloud deploy, Snowsight, interview walkthrough |

dbt Cloud uses subdirectory `sportsbook` and `dbt build --selector snowflake_deploy` (seeds skipped). Do **not** use Partner Connect.

## Layout

```
sportsbook/                 dbt project (profile: sportsbook)
  models/landing/           sources — PUT/COPY or seed. Not bronze.
  models/bronze/            brz_* views (rename, cast, dedupe)
  models/silver/            slv_* (ephemeral joins / FLATTEN)
  models/gold/finance/      fct_bets, mart_state_hold_ngr, sem_*
  models/gold/ops/          fct_payments, marts, dt_pending_withdrawals
  macros/                   generate_schema_name, from_landing, to_et
  snapshots/                snap_customer_vip
  selectors.yml             snowflake_deploy
data/                       CSVs for Snowflake PUT/COPY
snowflake/                  setup / load / teardown / debug runner
docs/course.md              living crash course
docs/dbt-cloud.md           Cloud + key-pair setup
STUDY.md                    this week's plan
```

`from_landing()` uses `source('landing', …)` on Snowflake and `ref()` on DuckDB so the same models run on both.

## Prerequisites

- Python 3.12+ and this repo’s `.venv` (`dbt-core`, `dbt-duckdb`, `dbt-snowflake`)
- From the **repo root**, use `.\.venv\Scripts\…` so you do not pick up another dbt
- New Cursor terminals start in `sportsbook/` and load `.env` via `snowflake/terminal_env.ps1`

```powershell
# first clone
python -m venv .venv
.\.venv\Scripts\pip.exe install -r requirements.txt
```

## 1. Local DuckDB

No Snowflake credentials. Prefer `sportsbook/` so dbt uses `sportsbook/profiles.yml` and does **not** load `~/.dbt` (other profiles there need `dbt-databricks`).

```powershell
cd sportsbook
$env:DBT_PROFILES_DIR = "."
dbt debug
dbt build
```

From the repo root:

```powershell
.\.venv\Scripts\dbt.exe debug --project-dir sportsbook --profiles-dir sportsbook
.\.venv\Scripts\dbt.exe build --project-dir sportsbook --profiles-dir sportsbook
```

Or `sportsbook/run_all.sh` (Day 1 seed → snapshot → build, then Day 2).

**Verified:** DuckDB `PASS=31`. Toy seeds: 19 bets / 10 payments / 9 KYC registrants.

## 2. Snowflake trial

This trial enforces **strong auth**. Local dbt and Cloud both use the PKCS#8 key at `~\.snowflake\dbt_cloud_rsa_key.p8` (outside the repo, never committed). Username/password is rejected.

### One-time auth

1. Copy `.env.example` → `.env` (gitignored).
2. Set `SNOWFLAKE_ACCOUNT` (hyphenated org-account, no `.snowflakecomputing.com`) and `SNOWFLAKE_USER`.
3. Keep the private key at `~\.snowflake\dbt_cloud_rsa_key.p8`, or set `SNOWFLAKE_PRIVATE_KEY_PATH`.
4. Public key must already be on the Snowflake user:

   ```sql
   ALTER USER "your_snowflake_username" SET RSA_PUBLIC_KEY='<headerless public key body>';
   ```

`snowflake/run.py` also fills missing account/user from `~/.dbt/profiles.yml`. It does not print secrets. It prefers the key file over a password.

| Variable | Required? | Default |
|---|---|---|
| `SNOWFLAKE_ACCOUNT` | Yes | — |
| `SNOWFLAKE_USER` | Yes | — |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | If the key is not in the default path | `~\.snowflake\dbt_cloud_rsa_key.p8` |
| `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` | Only if the key is encrypted | empty |
| `SNOWFLAKE_ROLE` | setup / teardown | `ACCOUNTADMIN` |
| `SNOWFLAKE_DBT_ROLE` | dbt | `TRANSFORMER` |
| `SNOWFLAKE_WAREHOUSE` | | `OPS_XS_WH` |
| `SNOWFLAKE_DATABASE` | | `FBG_PREP` |

### Check the connection

```powershell
# from repo root — loads .env + key, then dbt debug --target snowflake
.\.venv\Scripts\python.exe snowflake\run.py debug
```

After a new Cursor terminal (`terminal_env.ps1` already loaded `.env`):

```powershell
dbt debug --target snowflake
```

You should see `Connection test: [OK connection ok]` against `FBG_PREP` / `OPS_XS_WH` / `TRANSFORMER`.

Default `dbt debug` (no `--target`) is still DuckDB.

### Build the warehouse

From the repo root:

```powershell
.\.venv\Scripts\python.exe snowflake\run.py setup
.\.venv\Scripts\python.exe snowflake\run.py load
# inspect FBG_PREP.LANDING / BRONZE / GOLD in Snowsight
.\.venv\Scripts\python.exe snowflake\run.py teardown   # only when you want a clean slate
```

Shortcut that leaves objects built:

```powershell
.\.venv\Scripts\python.exe snowflake\run.py all
```

| Command | What it does |
|---|---|
| `setup` | Warehouse `OPS_XS_WH`, database `FBG_PREP`, schemas **LANDING / BRONZE / SILVER / GOLD**, roles `TRANSFORMER` and `OPS_ANALYST`, resource monitor |
| `load` | PUT `data/*.csv` → `@FBG_PREP.LANDING.MOCK_STAGE`, COPY INTO landing, then `dbt snapshot` + `dbt build --target snowflake` (seeds excluded) |
| `debug` | `dbt debug --target snowflake` with the key pair |
| `teardown` | Drop `FBG_PREP`, warehouse, resource monitor, roles — including every dbt object |
| `all` | `setup` + `load` |
| `sql path` | Any other `.sql` file on the same connection |

`setup` / `teardown` use `ACCOUNTADMIN`. `load` COPY + dbt use `TRANSFORMER`. `OPS_ANALYST` can read GOLD only.

**Verified:** landing 500 customers / 11,641 bets / 3,140 payments. Snowflake dbt `PASS=26`. `fct_bets` is 11,603 after test accounts are dropped.

More runner detail: [snowflake/README.md](snowflake/README.md).

## 3. dbt platform (Cloud)

Do **not** use Snowflake Partner Connect.

| Setting | Value |
|---|---|
| Repo | `WyattCurtis327/dbt-snowflake` |
| Project subdirectory | `sportsbook` |
| Database / warehouse / role | `FBG_PREP` / `OPS_XS_WH` / `TRANSFORMER` |
| Auth | Key pair (same public key as local). Paste the **private** key only in the Cloud UI |
| Job command | `dbt build --selector snowflake_deploy` |

Landing must already exist (`run.py load` or `all`). Cloud rebuilds bronze → gold; it does not PUT/COPY CSVs.

Full steps: [docs/dbt-cloud.md](docs/dbt-cloud.md).

## Naming

| Layer | Prefix | Materialization | Schema |
|---|---|---|---|
| Landing | `raw_*` (sources / seeds) | tables from COPY or seed | `LANDING` |
| Bronze | `brz_` | view | `BRONZE` |
| Silver | `slv_` | ephemeral | `SILVER` (no table) |
| Gold | `fct_` / `mart_` / `dt_` | table / dynamic table | `GOLD` |
| Semantic | `sem_` | table + MetricFlow YAML | `GOLD` |

Course and study plan: [docs/course.md](docs/course.md), [STUDY.md](STUDY.md).
