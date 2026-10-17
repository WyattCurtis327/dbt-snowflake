# Run the full project on Snowflake

From the repo root. Copy `.env.example` to `.env` or reuse `~/.dbt/profiles.yml` (the runner reads account/user/password from there and does not print them).

```powershell
copy .env.example .env
.\.venv\Scripts\python.exe snowflake\run.py setup
.\.venv\Scripts\python.exe snowflake\run.py load
.\.venv\Scripts\python.exe snowflake\run.py teardown
```

| Command | What it does |
|---|---|
| `setup` | Warehouse `OPS_XS_WH`, database `FBG_PREP`, schemas **LANDING / BRONZE / SILVER / GOLD**, roles, result-cache demo |
| `load` | PUT `data/*.csv` → `@FBG_PREP.LANDING.MOCK_STAGE`, COPY INTO landing tables, then `dbt snapshot` + `dbt build --target snowflake` (seeds excluded) |
| `teardown` | Drop `FBG_PREP`, warehouse, resource monitor, roles — including every dbt object |
| `all` | `setup` + `load`; leaves the project built so you can inspect it |
| `sql path` | Any other `.sql` file on the same connection |

`setup` and `teardown` need `SNOWFLAKE_ROLE=ACCOUNTADMIN`. `load` uses `TRANSFORMER` for COPY and dbt.

Landing is the first stop after PUT/COPY. It is **not** bronze. dbt then builds `brz_*` → `slv_*` → `fct_`/`mart_`/`sem_*`. `OPS_ANALYST` can read GOLD only.

Browser SSO: keep `SNOWFLAKE_AUTHENTICATOR=externalbrowser`. A browser window opens once per command.

Local DuckDB (no Snowflake): `cd sportsbook` and `dbt build`, or `./run_all.sh`.
