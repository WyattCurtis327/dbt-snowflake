# Connect this repo to dbt platform and deploy

Do **not** use Snowflake Partner Connect. That creates a managed jaffle_shop repo and new databases. This project already lives on GitHub and already has data in `FBG_PREP`.

**Verified** Sat 10/17/2026 on Developer tenant `https://rc086.us1.dbt.com/` (account Loandepot, 1-project max). Project `sportsbook` replaced the old Databricks Analytics project. Latest prod job: **Success** on SHA `72fa753` (`dbt build --selector snowflake_deploy`).

Official background: [Quickstart for dbt and Snowflake](https://docs.getdbt.com/guides/snowflake) (manual connect) and [Connect to GitHub](https://docs.getdbt.com/docs/cloud/git/connect-github).

## 0. Prereq

Landing and gold objects should already exist from the local runner:

```powershell
.\.venv\Scripts\python.exe snowflake\run.py all
```

dbt platform will **rebuild** bronze/silver/gold. It will **not** PUT/COPY CSVs. If you tore down, run `setup` + `load` first.

## 1. Create or open a dbt platform account

1. Go to [cloud.getdbt.com](https://cloud.getdbt.com/) (Developer plan is enough).
2. Sign in with the same email you use for GitHub if you can — it makes the GitHub App link easier.

## 2. Link GitHub

In dbt: **Account settings → Personal profile → Linked accounts → GitHub → Link**.

Install the dbt GitHub App on your user (or org) and grant it **WyattCurtis327/dbt-snowflake** only.

## 3. New project (not Partner Connect)

1. **Account settings → + New Project**. Name it `sportsbook`.
2. **Connection → Add new connection → Snowflake.** Use the trial you already run locally (the `dbt_snowflake` profile), **not** the Partner Connect `analytics` / `transforming` example:

   | Field | Value |
   |---|---|
   | Account | Hyphenated org-account in `~/.dbt/profiles.yml` (looks like `XXXXXX-XXXXXXX`). Do **not** append `.snowflakecomputing.com`. The numeric locator (`IU15163`) is the same account — do not mix them. |
   | Database | `FBG_PREP` |
   | Warehouse | `OPS_XS_WH` |
   | Role | `TRANSFORMER` |
   | Auth | Username/password for now (same user as the trial). Snowflake ends password auth for all users on **2026-08-31** — switch the Cloud connection to key-pair (deploy) or OAuth (dev) before then. Never commit the password. |

3. **Test connection** → Save.
4. **Your profile → Credentials → sportsbook** (dev environment):

   | Field | Value |
   |---|---|
   | Username | Your Snowflake login (email-style on this trial) |
   | Password | Same as `~/.dbt/profiles.yml` — paste it in the UI, never commit it |
   | Schema | `gold` (custom schemas `bronze` / `silver` / `gold` still win via `generate_schema_name`) |
   | Threads | `4` |

5. **Repository:** GitHub → `WyattCurtis327/dbt-snowflake`.
6. **Project subdirectory:** `sportsbook`  
   The `dbt_project.yml` is not at the repo root. If you skip this, Studio IDE will not see the project.

## 4. One development run

1. **Start developing in the Studio IDE.**
2. Confirm you see `models/bronze`, `models/silver`, `models/gold/finance`, `models/gold/ops`.
3. In the command bar:

   ```text
   dbt build --selector snowflake_deploy
   ```

   Or `dbt build` — seeds are disabled when `target.type == snowflake`, so they cannot overwrite landing.

## 5. Deploy (production job)

This tenant already has:

| Setting | Value |
|---|---|
| Project | `sportsbook` |
| Repo | `WyattCurtis327/dbt-snowflake` |
| Subdirectory | `sportsbook` |
| Environment | Production · dbt **v2 Stable** (Fusion 2.0.8) |
| Job | `sportsbook prod` |
| Command | `dbt build --selector snowflake_deploy` |
| Target name | `default` (logic keys off `target.type`, not `target.name`) |
| Source freshness | Off (Fusion v2 rejects `loaded_at_field` as `UnusedConfigKey`) |

1. **Deploy → Environments → + Create environment.**
   - Type: **Deployment** / Production
   - Connection: the Snowflake connection from step 3
   - Deployment credentials: same `TRANSFORMER` / `OPS_XS_WH` / `FBG_PREP`
2. **Deploy → Jobs → + Create job** (name: `sportsbook prod`).
   - Environment: the production environment
   - Commands:

     ```text
     dbt build --selector snowflake_deploy
     ```

   - Trigger: **Run now** first. Then add a schedule if you want (daily is enough for interview prep).
3. Open the run. You want green models/tests, **no `seed` steps**.

Expected Fusion summary on a clean clone of current `main`: **15 models | 10 data tests | 1 snapshot | 1 unit test** → 25 success, 1 warn (`dt_pending_withdrawals` no-op config change on reruns), 1 no-op (`slv_bet_legs` ephemeral).

After a successful job, Snowsight shows `FBG_PREP.LANDING` (COPY), `BRONZE` (`brz_*` views), `GOLD` (`fct_*` / `mart_*` / `dt_*` / `sem_time_spine` / `snap_customer_vip`). Silver `slv_bet_legs` is ephemeral and will not appear as an object.

Finance metrics (`cash_handle`, `cash_ggr`, `bonus_cost`, `hold_pct`, `ngr`) are declared on `fct_bets` with the [latest Semantic Layer YAML spec](https://docs.getdbt.com/docs/build/latest-metrics-spec). They are not a Snowflake `SEMANTIC VIEW` — that SQL is still Exercise 7 stretch / `[Not executed]`.

## 6. What not to do

- Do not `dbt seed` on Snowflake.
- Do not point the Cloud connection at `SNOWFLAKE_LEARNING_DB` / `SNOWFLAKE_LEARNING_WH`.
- Do not let Partner Connect create `PC_DBT_DB` and a managed repo, then try to merge that with this project.
- Do not put `{{ }}` around `source()` / `ref()` in Fusion snapshot YAML.
- Do not re-add `loaded_at_field` on landing sources while the job runs Fusion v2 — it is a hard parse error (`dbt1060`).
