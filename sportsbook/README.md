# dbt Charts boards

YAML dashboards next to the sportsbook models.

| Board | DuckDB | Snowflake `FBG_PREP.GOLD` |
|---|---|---|
| Finance (handle, GGR, hold, NGR) | http://localhost:8080/finance/ | http://localhost:8080/finance_snowflake/ |
| Payments | http://localhost:8080/payments/ | http://localhost:8080/payments_snowflake/ |
| KYC funnel | http://localhost:8080/kyc/ | http://localhost:8080/kyc_snowflake/ |
| VIP at bet time | http://localhost:8080/vip/ | http://localhost:8080/vip_snowflake/ |
| Ops (open bets, pending WD, bad beats) | http://localhost:8080/ops/ | http://localhost:8080/ops_snowflake/ |

The project venv is Python 3.14; dbt Charts 0.10 needs 3.11–3.13. Use the
separate `.venv-charts` at the repo root (created with `py -3.12`).

```powershell
# from repo root, after gold models exist
.\snowflake\terminal_env.ps1   # loads .env + key path; cds to sportsbook
..\.venv-charts\Scripts\dct.exe serve --port 8080
```

DuckDB works without `.env`. Snowflake needs the same key-pair env as
`dbt debug --target snowflake`. VIP inequality on Snowflake is empty until
`python snowflake/run.py replay-vip`.
