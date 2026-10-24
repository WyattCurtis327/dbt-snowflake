# dbt Charts boards

YAML dashboards next to the sportsbook models.

| Board | Source | URL when `dct serve --port 8080` |
|---|---|---|
| `charts/finance.yml` | DuckDB (`sportsbook.duckdb`) | http://localhost:8080/finance/ |
| `charts/finance_snowflake.yml` | Snowflake `FBG_PREP.GOLD` | http://localhost:8080/finance_snowflake/ |

The project venv is Python 3.14; dbt Charts 0.10 needs 3.11–3.13. Use the
separate `.venv-charts` at the repo root (created with `py -3.12`).

```powershell
# from repo root, after gold models exist
.\snowflake\terminal_env.ps1   # loads .env + key path; cds to sportsbook
..\.venv-charts\Scripts\dct.exe serve --port 8080
```

DuckDB works without `.env`. Snowflake needs the same key-pair env as `dbt debug --target snowflake`.
