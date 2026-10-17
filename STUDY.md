# Study plan — interview Thu Oct 22

Course source: [docs/course.md](docs/course.md) §5.

## Today — Sat 10/17 (~60 min)

1. Read course **§1** (business + KPI language): handle → hold % → GGR → promo cost → NGR → tax. 20 min.
2. If the trial is live, from the repo root: `python snowflake/run.py setup` then `python snowflake/run.py load`. That creates `OPS_XS_WH`, `FBG_PREP` (LANDING/BRONZE/SILVER/GOLD), loads CSVs into landing, and builds the dbt medallion (`brz_` → `slv_` → `fct_`/`mart_`/`sem_`). Start over with `python snowflake/run.py teardown`. Shortcut: `python snowflake/run.py all`. 25 min.
3. Run any `SELECT` twice. Confirm **result cache** in Query Profile (no warehouse credits on the second hit). 15 min.

You should be able to explain warehouses, credits, and RBAC aloud.

## Rest of the week

| When | Do this | Done when |
|---|---|---|
| **Sun 10/18** | dbt Fundamentals: models, sources, tests, docs (~45 min at 1.25x). Skim course §3.1–3.4. | You can say `ref` / `source` / test / contract without notes |
| **Mon 10/19** | Connect dbt platform to the trial. Upload `data/` CSVs with `snowflake/load_mock_data.sql`. Port **Ex 1** (`LATERAL FLATTEN`) and **Ex 4** (hold/NGR mart). | A real FLATTEN query ran in Snowflake |
| **Tue 10/20** | Port **Ex 2** (VIP snapshot) and **Ex 3** (incremental lookback). Break a table, then `CLONE … BEFORE(STATEMENT=>…)`. | You can whiteboard SCD2 and late-arriving data |
| **Wed 10/21** | Port **Ex 5** dynamic table. Re-read §0 and the JD. Rehearse the 5 sound bites + 3 questions. | Ready |
| **Thu 10/22 10:15 PT** | Re-read §0 and the KPI list. SQL scratchpad open. | Calm |

## Exercises already built (DuckDB)

Rehearse these in `sportsbook/`. Do not rebuild them from scratch.

| Ex | Point | Model |
|---|---|---|
| 1 | FLATTEN legs; lost-by-one parlay | `slv_bet_legs`, `mart_parlay_one_leg_away` |
| 2 | SCD2 VIP; join at bet time, not current tier | `snap_customer_vip`, `fct_bets_with_vip_tier` |
| 3 | Incremental MERGE + lookback or P10 disappears | `fct_payments`, `mart_payments_daily` |
| 4 | Hold / NGR / tax; exclude test accounts | `fct_bets`, `mart_state_hold_ngr` |
| 5 | Dynamic table as a view locally | `dt_pending_withdrawals` |
| 6 | KYC funnel in ET; `to_et` dispatch macro | `fct_kyc_funnel`, `mart_kyc_funnel_by_state` |
| 7 | Metrics once (MetricFlow YAML + Snowflake semantic view SQL) | `sem_bets`, `sem_time_spine` |

## Sound bites (say these, do not read them)

1. **Platform:** same architecture as Databricks; roles + future grants, per-second warehouses, `AT`/`BEFORE` + zero-copy clones for CI and backfills.
2. **Metrics / AI (lead with this):** Metric Views → Snowflake semantic views. One definition for Sigma and the agent. Descriptions and synonyms are the agent context.
3. **dbt bar:** grain, unique `unique_key`, incremental lookback, explicit TZ, test accounts out, unit test revenue logic. Late webhooks fail uniqueness tests; reconciliation catches them.
4. **Data Vault:** you know when it pays. Their Medallion + Mesh cut is the right weight. Bring keys/history/audit, not 28 hourly models.
5. **Ops is revenue:** withdrawal speed and KYC time move LTV; bonus abuse moves NGR; NY 51% tax doubles the value of every efficiency point.

## Questions for Andie

- Which Ops KPIs are least trusted — is there a GGR-style definition fight in CX or Payments?
- Does Ops own its own Mesh project? Who certifies metrics?
- Where are agents in Ops today, and how are they scored against humans?
- Split of stakeholder requests vs foundational work; what does a strong 90 days look like?
- How did the Sept 2 unified app change Ops data (CX drivers, KYC across OSB / casino / Markets)?
