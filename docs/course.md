# Snowflake + dbt Crash Course: Fanatics Betting & Gaming (Ops Analytics)

**For:** Wadi | **Interview:** Thu Oct 22, 2026, 11:00 AM PT, with Andie George (Sr. Manager, Strategic Operations) | **Role:** Manager, Data Analyst (Ops: CX, Fraud, Payments, WFM, VIP)
**Prepared:** Fri Oct 16, 2026 | **Builds on:** the 6-problem SQL warm-up and 5-exercise dbt drill (staging/QUALIFY dedupe, FRT SLA mart, schema tests, incremental withdrawals, fraud-rate code review). Nothing here repeats those.

> **How to use this:** Read section 0 first (10 min). Then follow the study plan in section 5. Sections 2–3 are reference material. The exercises in section 4 are the core practice. The repo's dbt project (`sportsbook/`) follows **landing → bronze (`brz_`) → silver (`slv_`) → gold (`fct_`/`mart_`/`dt_`) → semantic (`sem_`)**. From the repo root, `python snowflake/run.py setup` then `load` is the full Snowflake cycle (infra + landing COPY + dbt build). Local DuckDB: `cd sportsbook && dbt build`. Everything marked **[Snowflake-only]** needs the trial; **[Verified on dbt-duckdb]** was built locally.

---

## 0. The five things that matter most

1. **Fanatics' data stack is public, and it's Snowflake + dbt.** At Snowflake Summit 2026 (June), FBG's Senior Director of Data and Analytics Engineering Manager described the stack ([sfeir.dev write-up, in French](https://www.sfeir.dev/comment-fanatics-a-terrasse-le-chaos-des-donnees-grace-a-dbt-coco-et-snowflake-intelligence/)):
   - **Snowflake** is the warehouse and **dbt Cloud** handles transformation.
   - Models follow a **Medallion** layout: **landing** (PUT/COPY, not a transform layer) → **Bronze** = 1:1 staging (`brz_*`) → **Silver** = joins and business rules (`slv_*`) → **Gold** = aggregates and **centrally defined metrics** such as GGR (`fct_`/`mart_`/`sem_*`). Do not call the landing schema bronze.
   - **dbt Mesh** gives domain teams their own dbt projects that use cross-project refs to read certified models.
   - **Cortex Code** is the AI coding assistant.
   - **Snowflake Intelligence** agents run on **semantic views** over the Gold models.
   - The original problem was conflicting definitions: Marketing, Finance, and others each calculated GGR differently.
   - They retired a **Data Vault** layer. It had been 28 hourly models costing about $300/day; it became 4 Silver models at about $80/day.

   FBG's Luke Kranz (Senior Staff AI Engineer) is also listed for a dbt Summit session, "From hard lessons to AI-ready analytics: Fanatics' journey with dbt and Snowflake" ([dbt Summit](https://www.getdbt.com/dbt-summit/speakers/luke-kranz)).
2. **The job posting is about trusted metrics more than modeling.** The JD says the role will "own the quality and reliability of the dbt models," "set and hold the technical bar through direct review of SQL, dbt models," and "provide the trusted data, metrics, and evaluation frameworks needed to support agent development." It also mentions Sigma/Tableau and a **live, on-screen technical exercise** ([JD on Greenhouse](https://job-boards.greenhouse.io/fanaticsfbg/jobs/4426025009)).
3. **Your Databricks Metric Views experience is directly relevant.** Metric Views in Unity Catalog are close to Snowflake semantic views, which FBG uses for Snowflake Intelligence. That is the strongest bridge you have.
4. **Be careful how you bring up Data Vault.** FBG publicly moved away from it for cost and complexity reasons. Present your DV experience as "I know when it pays off and when Medallion plus dbt is the right weight." Don't pitch DV.
5. **Know the language of the business:** handle → hold % → GGR → promo/bonus cost → NGR → state tax. Ops metrics feed into these numbers: fraud and bonus abuse raise promo cost, slow withdrawals hurt retention, and VIP churn moves NGR.

---

## 1. Fanatics Betting & Gaming: business model in brief (sourced)

### 1.1 What FBG is
- **One unified app, launched Sep 2, 2026.** It is called "Fanatics Sports & Casino" and has one account, one FanCash balance, and Fanatics ONE loyalty ([GlobeNewswire via Markets Insider](https://markets.businessinsider.com/news/stocks/fanatics-introduces-fanatics-sports-casino-one-app-for-fans-to-bet-trade-or-play-1036515892)). It contains:
  - **Sportsbook (OSB):** 23 states + DC.
  - **iGaming/Casino:** MI, NJ, PA, WV. Ontario, Canada is also listed on [fanaticsinc.com](https://www.fanaticsinc.com/fanatics-sportsbook-online-experience).
  - **Fanatics Markets:** a CFTC-regulated event-contracts (prediction market) product in 22 states + 4 territories, including CA, TX, and FL, where sportsbooks aren't legal ([availability](https://fanaticsmarkets.com/legal/availability)).
- **History**
  - Online sportsbook launched Aug 2023 in MD, MA, OH, and TN ([iGaming Business](https://igamingbusiness.com/sports-betting/product-technology-sports-betting/fanatics-launches-online-sportsbook-in-four-states/)).
  - Acquired PointsBet's US business; the deal closed April 2024 ([Fanatics IR](https://investor.fanatics.com/news/news-details/2024/Fanatics-Betting-and-Gaming-Closes-its-Acquisition-of-the-US-Businesses-of-PointsBet/default.aspx)).
- **Scale and trajectory.** FBG is private, so all figures below are statements or estimates, not audited numbers.
  - Rubin told Bloomberg that betting will book **about $2B revenue in 2026** and is **still loss-making**.
  - Betting ad spend goes from about **$350M in 2026 to $800M–$1B in 2027**.
  - The betting business will generate **more than $1B of FanCash** this year.
  - The CFO said Fanatics has about **22–23M customers a year**. About **3% buy from more than one Fanatics business**, and those customers spend about **5x** as much.
  - Source for all four: [iGaming Express, Oct 5, 2026](https://igamingexpress.com/michael-rubin-says-betting-got-harder-fanatics-plans-to-spend-up-to-1-billion-anyway/).
  - In Sep 2025 Rubin projected losses of about $300M in 2025 and about $150M in 2026, with profit in 2027 ([InGame](https://www.ingame.com/rubin-fanatics-revenue-sports-betting/)). The larger 2027 marketing budget pushes that timeline out.
- **Market share** (approximate; states report differently):
  - Third behind FanDuel and DraftKings. Over the 12 months to Jul 2026: FanDuel 39%, DraftKings 34%, **Fanatics 8%** of online sportsbook revenue in the 12 states that report by operator. Fanatics was **8.8% in Jul 2026** ([Gambling Atlas](https://gamblingatlas.org/charts/us-sportsbook-market-share/)).
  - Casino Reports puts Fanatics at about **9.0% of handle and 9.3% of GGR** ([Casino Reports](https://www.casinoreports.com/sports-betting-data/)).
  - **New York, Aug 2026:** Fanatics took 11% of state revenue and grew revenue 17% YoY while the market fell 6% (NYSGC data via [iGaming Express](https://igamingexpress.com/michael-rubin-says-betting-got-harder-fanatics-plans-to-spend-up-to-1-billion-anyway/)).

### 1.2 How a sportsbook makes money (with the definitions you'll be asked to defend)
| Term | Definition | Ops-analytics gotcha |
|---|---|---|
| **Handle** | Total amount wagered. Usually counted on settled bets for hold; on placed bets for volume. | Exclude voids/cancels. Separate cash and bonus stakes. Placed-date vs settled-date handle differ, especially for futures. |
| **GGR** (gross gaming revenue) | Stakes minus winnings paid. | FBG publicly admitted to multiple GGR definitions before centralizing ([Summit talk](https://www.sfeir.dev/comment-fanatics-a-terrasse-le-chaos-des-donnees-grace-a-dbt-coco-et-snowflake-intelligence/)). Always ask "which GGR?" |
| **Hold %** | GGR ÷ handle. | Very volatile on small samples or with whale wins. Parlays and SGPs carry higher theoretical hold than straight bets. Report actual hold alongside expected (theoretical) hold. |
| **Promo / bonus cost** | Bonus bets, profit boosts, deposit matches, odds boosts, FanCash. | Accounting varies. Some states let operators deduct promos from taxable revenue and some don't. For example, NY doesn't allow promo deductions, and CO phased out its free-bet deduction by Jul 1, 2026 ([CASPR](https://caspr.org/state-gambling-scorecard/taxes/)). |
| **NGR** (net gaming revenue) | GGR minus promo/bonus cost (and sometimes other adjustments). | Ops affects this directly: **bonus abuse/multi-accounting** inflates promo cost; **chargebacks** reduce it. |
| **Gaming tax** | A state rate on GGR/AGR (taxable base varies). | NY online **51%**, PA **34%**, IL progressive **up to 40% plus $0.25–$0.50 per wager**, NJ **19.75%**, OH **20%**, MD/MA **20%**, NC **18%**, MI **8.4%**, and TN **1.85% of handle** (taxes handle, not GGR) ([CASPR](https://caspr.org/state-gambling-scorecard/taxes/)). The same GGR is worth very different amounts after tax depending on the state. |
| **CAC / LTV** | Acquisition cost per first-time depositor (FTD) vs lifetime NGR (or contribution margin). | Rubin said prediction markets have raised the cost of every customer and that customers are "easily poached" ([iGaming Express](https://igamingexpress.com/michael-rubin-says-betting-got-harder-fanatics-plans-to-spend-up-to-1-billion-anyway/)). Retention, CX, and payments quality therefore move LTV directly. |

### 1.3 The Fanatics advantage: FanCash and the ecosystem
- **FanCash** is Fanatics' loyalty currency, redeemable across Fanatics businesses for apparel, bonus bets, profit boosts, and collectibles ([FanCash page](https://www.fanatics.com/fancash/x-5550)).
- **Sportsbook earn rates** scale with odds: **up to 1%** of stake at +410 or shorter, rising to **9–10%** at +14500 or longer. Casino earns are 0.25% on slots, 0.20% on table games, and 0.05% on blackjack, craps, baccarat, and video poker ([FanCash terms](https://sportsbook.fanatics.com/legal/fancash-program-terms/)).
- **Analytics implications**
  - FanCash is a **real promo cost line**: more than $1B was generated by betting this year, per Rubin.
  - It creates **cross-sell attribution** questions, for example "did a bettor buy a jersey?" (about 3% of customers are multi-business today).
  - It's a **fraud surface** (earn/burn abuse).
  - It's a **VIP lever**.

### 1.4 Ops KPIs by function (definitions; no benchmarks invented)
I didn't find public FBG targets for these KPIs. Ask Andie which ones are current pain points.

**CX (customer support)**
- **First response time (FRT)** and **time to resolution** (p50/p90, in business hours vs clock hours). Breach rate against SLA by channel (chat/email/phone) and queue.
- **Contact rate:** contacts per 1,000 active users or per 1,000 bets. It normalizes for NFL-Sunday volume swings.
- **FCR** (first contact resolution), reopen rate, escalation rate, **CSAT**, and top contact drivers (withdrawal status, KYC, bet settlement disputes, promo eligibility).
- **AI/agent metrics** (the JD's AI-first angle): containment/deflection rate, handoff rate, CSAT for agent-handled vs human-handled contacts, and an accuracy audit sample. Human-in-the-loop review rate.

**Fraud / KYC / AML**
- **KYC funnel:** registered → KYC submitted → passed (auto vs manual review) → first deposit → first bet. Measure **time-to-verify** and **manual review rate**.
- **Fraud:** chargeback rate (count and $), account takeover incidents, **multi-accounting / bonus abuse** detection rate, and the **false-positive rate** (good customers blocked, which is both a CX and a revenue cost).
- **Responsible gaming / compliance tie-ins:** geolocation-block rate and self-excluded-player detection.
- **AML/BSA:** BSA-covered casinos file CTRs for cash-in or cash-out over **$10,000** in a gaming day, and SARs for suspicious activity of **$5,000 or more** ([12 CFR/31 CFR 1021.311 via Federal Reserve](https://www.federalreserve.gov/frrs/regulations/section-1021311-filing-obligations.htm); [FinCEN casino SAR guidance](https://www.fincen.gov/sites/default/files/guidance/casinosarguidancefinal1203.pdf)). Ops analytics typically tracks alert volume, alert-to-case rate, case aging, and filing timeliness.

**Payments**
- **Deposit success/approval rate** by method, issuer/BIN, and state. Track **decline reason mix** (issuer declines for gambling MCC are a big driver industry-wide).
- **Withdrawal time:** request → approved → paid, at p50/p90, by method. Track **pending-queue aging**, the share of withdrawals held for manual review, and withdrawal cancel/reversal rate.
- **Payment cost per transaction** and chargeback rate.
- **Retention link:** time-to-withdraw and withdrawal success → repeat deposit rate. Use matched cohorts rather than a naive correlation.

**WFM (workforce management)**
- **Volume forecast accuracy** (MAPE/WAPE by interval) and **service level** (% answered within X seconds).
- **ASA** (average speed of answer) and **abandon rate**.
- **Occupancy** vs **utilization**, **shrinkage**, **schedule adherence**, and **AHT** (feeds Erlang C staffing).
- **Seasonality drivers:** NFL Sundays/MNF, March Madness, Super Bowl, promo launches, and new-state launches.

**VIP / responsible gaming**
- **VIP:** tier migration (needs SCD2; see Exercise 2), NGR concentration (the top 1% share of NGR), churn/early-warning (days since last bet vs personal baseline), host contact cadence, and VIP withdrawal SLA.
- **Responsible gaming:** FBG offers deposit limits (daily/weekly/monthly), single-wager and time-based wager limits, session time limits, timeouts (3–365 days), self-exclusion (minimum 1 year), and deposit-method exclusion. **Decreases to a limit take effect immediately; increases wait for the current period to lapse** ([FBG Responsible Gaming](https://sportsbook.fanatics.com/legal/responsible-gaming/)). KPIs to track: % of actives with any limit set, limit-change events, timeouts/self-exclusions, and RG interventions. Make sure VIP programs never market to self-excluded accounts; the data join is the safeguard.

---

## 2. Snowflake for a Databricks person

### 2.1 Architecture in 90 seconds
- **Three layers:** **storage** (compressed columnar **micro-partitions** in cloud object storage, managed by Snowflake), **compute** (**virtual warehouses**: independent clusters you size and pause), and **cloud services** (metadata, optimizer, security, result cache).
- **Storage and compute are separate**, as in Databricks. The difference is that you never manage files, Delta logs, OPTIMIZE, or VACUUM.
- **Virtual warehouse = Databricks SQL warehouse.**
  - Sizes run from XS up; each step **doubles credits/hour** (XS = 1 credit/hr, S = 2, M = 4, ...).
  - Billing is **per second with a 60-second minimum** each time a warehouse starts or resumes ([docs](https://docs.snowflake.com/en/user-guide/cost-understanding-compute)).
  - Set `AUTO_SUSPEND` (e.g., 60s) and `AUTO_RESUME = TRUE`.
  - **Multi-cluster warehouses** scale *out* for concurrency (many dashboards on NFL Sunday). Resizing scales *up* for heavy single queries.
- **Credits = DBUs, roughly.** Cost is credits × $/credit (by edition/region), plus storage (TB/month) and serverless features (tasks, dynamic table refreshes, auto-clustering, search optimization, Cortex).
- **Three caches:**
  1. **Result cache:** an identical query on unchanged data returns free for 24 hours ([docs](https://docs.snowflake.com/en/user-guide/querying-persisted-results)).
  2. **Warehouse local disk cache:** warm SSD data, lost on suspend. This is the trade-off with aggressive auto-suspend.
  3. **Metadata cache:** `COUNT(*)` and `MIN`/`MAX` can be answered without a warehouse.
- **Micro-partitions** are 50–500 MB uncompressed, immutable, created automatically, and carry min/max metadata per column. **Pruning** works like Delta data skipping.
- **Clustering keys** (≈ Liquid Clustering/Z-order) are only worth it on large tables with selective filters, e.g., `fct_bets CLUSTER BY (settled_date_et, state)`. Automatic Clustering charges serverless credits, so check `SYSTEM$CLUSTERING_INFORMATION` first ([docs](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)).

### 2.2 Security: Snowflake RBAC vs Unity Catalog
- **Namespace:** `DATABASE.SCHEMA.OBJECT` ≈ UC `catalog.schema.table`. Unquoted identifiers are **upper-cased**; avoid quoted mixed-case names.
- **Privileges go to roles, roles go to users** (and to other roles, forming a hierarchy). A session runs with a **primary role** (`USE ROLE`) plus optional secondary roles. UC grants directly to users, groups, and service principals.
- **System roles:** `ACCOUNTADMIN` (break-glass), `SECURITYADMIN` (grants), `USERADMIN`, `SYSADMIN` (should own databases and warehouses), and `PUBLIC`.
- **Recommended pattern:** *access roles* (e.g., `OPS_ANALYTICS_READ` on `ANALYTICS.OPS_MARTS`) granted to *functional roles* (`OPS_ANALYST`), which are granted to users. Use **future grants** (`GRANT SELECT ON FUTURE TABLES IN SCHEMA ...`) so new dbt models are readable without manual grants.
- **Ownership matters.** The role that creates an object owns it, so dbt's role should own what dbt builds.
- **Column masking policies** ≈ UC column masks. **Row access policies** ≈ UC row filters. **Object tags** and tag-based masking handle PII (DOB, SSN last 4, address from KYC). dbt can attach `row_access_policy` and `table_tag` configs ([dbt Snowflake configs](https://docs.getdbt.com/reference/resource-configs/snowflake-configs)).
- **Secure views** hide the view definition, at some performance cost.

### 2.3 Time Travel, zero-copy clone, Fail-safe
```sql
-- [Snowflake-only, NOT executed]
SELECT * FROM fct_payments AT(OFFSET => -60*60);                       -- 1 hour ago
SELECT * FROM fct_payments AT(TIMESTAMP => '2026-10-16 08:00'::timestamp_ltz);
SELECT * FROM fct_payments BEFORE(STATEMENT => '<query_id>');         -- before a bad MERGE
UNDROP TABLE fct_payments;
CREATE TABLE fct_payments_restored CLONE fct_payments BEFORE(STATEMENT => '<query_id>');
CREATE DATABASE analytics_ci CLONE analytics;                          -- instant, zero-copy, for CI/testing
```
- **Retention:** default 1 day; up to 90 days on Enterprise edition. After that, permanent tables get **7 days of Fail-safe** (recoverable only by Snowflake support; [docs](https://docs.snowflake.com/en/user-guide/data-failsafe)).
- **dbt creates transient tables by default on Snowflake** (no Fail-safe, at most 1 day of Time Travel), which saves storage ([dbt docs](https://docs.getdbt.com/reference/resource-configs/snowflake-configs)). Set `+transient: false` for anything you need to recover.
- **Databricks mapping:** `VERSION/TIMESTAMP AS OF` ≈ `AT/BEFORE`. `SHALLOW CLONE` ≈ zero-copy clone (closest analog). `RESTORE` ≈ clone-before-statement or `UNDROP`.

### 2.4 Streams and tasks (CDC + scheduling inside Snowflake)
```sql
-- [Snowflake-only, NOT executed]
CREATE OR REPLACE STREAM raw.payments_stream ON TABLE raw.payments;   -- tracks inserts/updates/deletes since last consume
CREATE OR REPLACE TASK ops.t_merge_payments
  WAREHOUSE = OPS_XS_WH
  SCHEDULE = '5 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('raw.payments_stream')                  -- skip (no cost) when nothing changed
AS
  MERGE INTO ops.payments_current t
  USING (SELECT * FROM raw.payments_stream WHERE METADATA$ACTION = 'INSERT') s
  ON t.payment_id = s.payment_id
  WHEN MATCHED THEN UPDATE SET status = s.status, completed_at = s.completed_at, updated_at = s.updated_at
  WHEN NOT MATCHED THEN INSERT (payment_id, customer_id, status, requested_at, completed_at, updated_at)
                        VALUES (s.payment_id, s.customer_id, s.status, s.requested_at, s.completed_at, s.updated_at);
ALTER TASK ops.t_merge_payments RESUME;                                -- tasks are created SUSPENDED
```
- A **stream** ≈ Delta Change Data Feed. It has an offset, and reading it in DML advances the offset. Rows have `METADATA$ACTION` / `METADATA$ISUPDATE`; an update appears as a DELETE+INSERT pair.
- A **task** ≈ a Databricks Job (CRON or interval; serverless or warehouse). Tasks can form DAGs (`AFTER`).
- **At FBG, dbt Cloud is the orchestrator for models.** Streams and tasks are more for near-real-time or platform work. Know them, but expect to work mostly in dbt.

### 2.5 Dynamic tables (Snowflake's answer to DLT / materialized views)
- **Declarative:** you write a SELECT and set a `TARGET_LAG` (e.g., `'5 minutes'` or `DOWNSTREAM`). Snowflake keeps the result fresh, incrementally when possible ([docs](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)).
- **Good fit for Ops:** a near-real-time **pending-withdrawals queue**, CX backlog by queue, or a live KYC manual-review queue.
- **Gotchas**
  - Non-deterministic functions like `CURRENT_TIMESTAMP()` can block incremental refresh. Compute "age" downstream instead.
  - Some constructs force a full refresh.
  - Refreshes cost warehouse credits.
- **dbt support:** `materialized='dynamic_table'` with `target_lag` and `snowflake_warehouse`. Changing the SQL requires `--full-refresh`. In dbt, if you omit `target_lag`, dbt sets `scheduler: DISABLE` and refreshes it during `dbt run` ([dbt docs](https://docs.getdbt.com/reference/resource-configs/snowflake-configs)).
- **Databricks mapping:** Lakeflow Declarative Pipelines (DLT) / materialized views / streaming tables.

### 2.6 Semi-structured: VARIANT, `:` paths, FLATTEN
- **`VARIANT`** holds JSON (up to 128 MB per value in current docs); `OBJECT` and `ARRAY` are also available ([docs](https://docs.snowflake.com/en/sql-reference/data-types-semistructured)).
- **Path access and casting:** `payload:legs[0]:american_odds::number`, `GET_PATH`. Use `TRY_PARSE_JSON` for dirty input.
- **`LATERAL FLATTEN(input => col)`** returns `SEQ, KEY, PATH, INDEX, VALUE, THIS`. Use `OUTER => TRUE` to keep rows with empty arrays, like a LEFT JOIN ([docs](https://docs.snowflake.com/en/sql-reference/functions/flatten)).
- **Databricks mapping:** `explode(from_json(...))` / `LATERAL VIEW explode`, the `:` path syntax on JSON strings, and the newer `VARIANT` type.

### 2.7 SQL dialect points you'll hit in a live exercise
- **`QUALIFY`** works the same as in Databricks; you've already drilled it.
- **Time zones** matter: Ops reports usually use ET or the state's local day, while events are in UTC.
  - Types: `TIMESTAMP_NTZ` (default for `TIMESTAMP`), `TIMESTAMP_LTZ`, `TIMESTAMP_TZ`.
  - The 3-arg form `CONVERT_TIMEZONE('UTC','America/New_York', ts_ntz)` converts NTZ wall-clock. The 2-arg form `CONVERT_TIMEZONE('America/New_York', ts_tz_or_ltz)` converts TZ/LTZ ([docs](https://docs.snowflake.com/en/sql-reference/functions/convert_timezone)).
  - Databricks equivalent: `from_utc_timestamp(ts, 'America/New_York')`.
- **`DATEDIFF('minute', a, b)`** counts **boundaries crossed**, not elapsed duration. For SLA math, use `DATEDIFF('second', a, b)/60.0`. `TIMESTAMPDIFF` is an alias.
- **`MERGE`:** if more than one source row matches a target row, Snowflake raises a **nondeterministic merge** error by default ([docs](https://docs.snowflake.com/en/sql-reference/sql/merge)). Dedupe the source first with `QUALIFY ROW_NUMBER()...=1`. In dbt, a non-unique `unique_key` causes the same failure.
- **Also useful:** `IFF(cond, a, b)`, `ZEROIFNULL`, `DIV0`/`DIV0NULL` (safe divide), `TRY_TO_NUMBER`, `ILIKE`, `LISTAGG`, `ARRAY_AGG`, `OBJECT_CONSTRUCT`, `MEDIAN`, `APPROX_PERCENTILE`, `PERCENTILE_CONT(...) WITHIN GROUP`, `TIME_SLICE(ts, 15, 'MINUTE')` (WFM intervals), `GENERATOR` (date spines), and `SAMPLE`.

### 2.8 Cost hygiene: what an Ops Analytics manager should enforce
- Use **separate warehouses** per workload (`TRANSFORM_WH` for dbt, `BI_WH` for Sigma/Tableau, `ADHOC_WH` for analysts). XS/S by default, `AUTO_SUSPEND = 60`.
- Put **resource monitors** on credit quotas with notify/suspend thresholds ([docs](https://docs.snowflake.com/en/user-guide/resource-monitors)).
- Use **query tags** (dbt `query_tag`) and `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` / `WAREHOUSE_METERING_HISTORY` to attribute cost per model or dashboard.
- **Incremental models** for large facts (bets, payments, CX events). Don't full-rebuild hourly. FBG's Data Vault → Medallion cut ($300 → $80/day) is the example to cite.
- Don't `SELECT *` from huge VARIANT columns in BI. Flatten once in Silver.
- Check the Query Profile for **"bytes spilled to remote storage"** (warehouse too small) and **"partitions scanned / total"** (pruning failing).
- **Sigma** sends live SQL to Snowflake, so dashboard design directly drives warehouse cost. Keep dashboards on Gold aggregates.

### 2.9 Side-by-side cheat sheet
| Concept | Databricks / Unity Catalog | Snowflake |
|---|---|---|
| Namespace | `catalog.schema.table` | `DATABASE.SCHEMA.OBJECT` |
| Compute | SQL warehouse / cluster, DBUs | Virtual warehouse, credits (per-sec, 60s min) |
| Scale for concurrency | Serverless SQL autoscale | Multi-cluster warehouse |
| Storage format | Delta files you can see (OPTIMIZE/VACUUM) | Micro-partitions, fully managed (Iceberg tables optional) |
| Data layout | Liquid clustering / Z-order | Clustering keys + Automatic Clustering |
| Permissions | GRANT to users/groups/SPs | GRANT to **roles**; roles to users; `USE ROLE` |
| Row/column security | Row filters / column masks | Row access policies / masking policies (tag-based) |
| History | `SELECT ... VERSION AS OF` / `TIMESTAMP AS OF` | `AT(TIMESTAMP=>…)` / `BEFORE(STATEMENT=>…)`, `UNDROP` |
| Clone | `SHALLOW/DEEP CLONE` | `CLONE` (zero-copy, db/schema/table) |
| CDC | Change Data Feed | Streams |
| Scheduling | Jobs / Workflows | Tasks (DAGs) |
| Declarative pipelines | DLT / Lakeflow, materialized views | Dynamic tables |
| Semantic metrics | **UC Metric Views** | **Semantic views** (+ Cortex Analyst / Snowflake Intelligence) |
| JSON | `from_json`, `explode`, `col:path`, VARIANT | `PARSE_JSON`, `col:path::type`, `LATERAL FLATTEN` |
| Time zone | `from_utc_timestamp(ts,'America/New_York')` | `CONVERT_TIMEZONE('UTC','America/New_York',ts)` |
| Upsert | `MERGE INTO` (Delta) | `MERGE INTO` (errors on nondeterministic matches) |
| Safe divide | `try_divide(a,b)` | `DIV0NULL(a,b)` or `a/NULLIF(b,0)` |
| Python | Notebooks / PySpark | Snowpark (DataFrames similar to PySpark), Streamlit in Snowflake |
| AI assistant | Databricks Assistant / Genie | Cortex Code / Cortex Analyst / Snowflake Intelligence |

---

## 3. dbt on Snowflake, tied to a sportsbook

> **Naming note (2026):** dbt Labs has dropped the "dbt Core" / "Fusion" product names. There is now **dbt v1** (the Python engine, formerly Core) and **dbt v2** (the Rust engine, now the default), and **"dbt platform"** is what used to be called dbt Cloud ([dbt docs](https://docs.getdbt.com/docs/introduction)). FBG's talk still says "dbt Cloud." Use whichever term the interviewer uses.

### 3.1 Project layout (this repo = FBG Medallion + an explicit landing zone)
```
FBG_PREP.LANDING     # PUT/COPY (or dbt seed locally). source('landing'). NOT bronze.
models/
  landing/           # _sources.yml only
  bronze/            # brz_*: 1:1 with landing, rename/cast/dedupe; views
  silver/            # slv_*: joins + business rules; ephemeral/views/tables
  gold/
    finance/         # fct_bets, mart_state_hold_ngr, sem_time_spine, _semantic.yml
    ops/             # fct_payments, fct_kyc_funnel, mart_*, dt_pending_withdrawals
snapshots/           # SCD2: snap_customer_vip (reads landing)
seeds/               # local landing tables (DuckDB). Snowflake uses COPY instead.
tests/               # singular tests
macros/              # to_et(), american_to_decimal(), generate_schema_name()
```
Prefixes: `brz_` bronze, `slv_` silver, `fct_`/`mart_`/`dt_` gold, `sem_` semantic.

On Snowflake, `python snowflake/run.py setup` creates LANDING/BRONZE/SILVER/GOLD. `load` COPYs into LANDING then runs dbt so objects exist in those schemas. `OPS_ANALYST` reads GOLD only.

Reference: [How we structure our dbt projects](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview). Talking point: Databricks people often call RAW "bronze." FBG's Summit talk calls staging Bronze. This project keeps landing separate so you can say both.

**With dbt Mesh at FBG,** Ops Analytics likely owns its own project. It would `ref()` the central team's certified models (e.g., `{{ ref('core', 'fct_bets') }}`) instead of rebuilding GGR ([dbt Mesh](https://docs.getdbt.com/docs/mesh/about-mesh)). Key concepts:
- model **access** (`public`/`protected`/`private`)
- **groups/owners**
- **model contracts** (enforced column names and types)
- **model versions**

### 3.2 Sources and refs
- **`source()`** declares raw tables and enables **source freshness** (`loaded_at_field` + `warn_after`/`error_after`), so you know before Andie does that the CX ticket feed is stale.
  - Snowflake caveat: freshness without a `loaded_at_field` uses `LAST_ALTERED`, which also changes on DDL and background maintenance ([dbt docs](https://docs.getdbt.com/reference/resource-configs/snowflake-configs)). Always set a `loaded_at_field`.
- **`ref()`** builds the DAG and handles environment-aware schemas (dev vs prod vs CI).

### 3.3 Materializations, mapped to sportsbook models
| Materialization | Use at FBG Ops | Snowflake specifics |
|---|---|---|
| `view` | `brz_*` | Cheap; computed at query time. |
| `ephemeral` | small `slv_*` CTEs (e.g., `slv_bet_legs`) | Inlined as a CTE; not queryable. Unit-test mocks need `format: sql` (learned the hard way in Exercise 6). |
| `table` | `dim_customer`, `mart_state_hold_ngr`, daily KPI marts | `cluster_by` supported. **Transient by default.** |
| `incremental` (`merge`) | `fct_bets`, `fct_payments`, `fct_cx_tickets` | Default strategy is `merge` on `unique_key`. Others: `append`, `delete+insert`, `insert_overwrite` (full truncate+insert on Snowflake), `microbatch` ([docs](https://docs.getdbt.com/docs/build/incremental-strategy)). |
| `dynamic_table` | near-real-time queues (pending withdrawals, CX backlog) | `target_lag`, `snowflake_warehouse`. SQL changes need `--full-refresh`. No model contracts. |
| `snapshot` | `snap_customer_vip`, `snap_kyc_status`, `snap_limit_settings` | SCD2 with `dbt_valid_from`/`dbt_valid_to`. |
| `semantic_view` (package) | Gold metrics for Snowflake Intelligence | Via the `Snowflake-Labs/dbt_semantic_view` package ([docs](https://docs.getdbt.com/reference/resource-configs/snowflake-configs)). |

### 3.4 Tests
- **Generic data tests:** `unique`, `not_null`, `accepted_values`, `relationships`, plus `dbt_utils` / `dbt_expectations`.
- **Singular tests:** SQL that returns failing rows.
- **Severity / thresholds:** `severity: warn`, `warn_if`, `error_if`. You covered the basics already.
- **New for this course:**
  - **Unit tests** (dbt 1.8+) check *logic* on mocked inputs before data exists ([docs](https://docs.getdbt.com/docs/build/unit-tests)). Exercise 6 has one for the GGR/bonus logic.
  - **Severity design:** a hold-% range check should **warn**, not fail. Small samples can legitimately breach −100%; the toy data did exactly that, at NJ −180% before more bets were added.
  - **Model contracts** on public Mesh models, so a column rename upstream fails CI instead of breaking a Sigma dashboard.

### 3.5 Snapshots (SCD2): VIP tier changes
Since dbt 1.9, snapshots are configured in **YAML** ([docs](https://docs.getdbt.com/docs/build/snapshots)):
- `strategy: timestamp` (uses `updated_at`) or `check` (compares `check_cols`)
- `hard_deletes: ignore | invalidate | new_record`
- `dbt_valid_to_current` (e.g., `9999-12-31`, which removes `COALESCE` from range joins)

**Rules of thumb**
- Snapshot **sources**, not marts.
- Run snapshots on a schedule frequent enough to catch every change. A snapshot only sees the state at run time, so two tier changes between runs collapse into one.
- If the source keeps its own history (e.g., a `vip_tier_changes` event table), build SCD2 from the events with window functions instead.

### 3.6 Semantic layer and metrics: three options to talk about
1. **dbt Semantic Layer (MetricFlow):** `semantic_models` (entities, dimensions, measures) plus `metrics` (simple, ratio, derived, cumulative, conversion) ([docs](https://docs.getdbt.com/docs/use-dbt-semantic-layer/dbt-sl)). Example YAML is in Exercise 7; it was **parse-validated** locally but not queried.
2. **Snowflake semantic views,** which FBG uses under Snowflake Intelligence ([docs](https://docs.snowflake.com/en/user-guide/views-semantic/overview)). They can be managed from dbt with the `dbt_semantic_view` package.
3. **BI-layer metrics** (Sigma/Tableau calcs). This is where FBG *came from*, and the Summit talk was about moving logic *out of* Tableau.

**Your angle:** "Metrics belong in the warehouse, versioned and tested. The BI layer and the agents both read the same definition. That's what I did with Databricks Metric Views."

### 3.7 CI / slim CI, docs and lineage, Cloud vs Core
- **Slim CI** ([docs](https://docs.getdbt.com/docs/deploy/continuous-integration)): on each PR, build only changed models and their children against prod state, deferring unchanged parents to prod: `dbt build --select state:modified+ --defer --state <prod-manifest>`. On Snowflake, the CI job builds into a PR-specific schema (`dbt_cloud_pr_<id>_...`); zero-copy clones are an option for heavier testing.
- **PR checklist you'd enforce as manager:**
  - grain stated and tested
  - `unique_key` truly unique
  - incremental lookback for late data
  - time-zone handling explicit
  - test accounts excluded (FBG hit this exact issue across 100+ models, per the Summit talk)
  - metric changes reviewed by the metric owner
- **Docs and lineage:** `dbt docs generate` / dbt Catalog (formerly Explorer) for column-level lineage. Descriptions feed both humans and **AI agents**; FBG's semantic views include descriptions, synonyms, and verified queries.
- **dbt platform (Cloud) vs v1/Core**
  - The platform adds the IDE (Studio), scheduler, CI jobs, Catalog, Semantic Layer APIs, Mesh cross-project refs, and Copilot.
  - Core/v1 is the open-source CLI you orchestrate yourself (Airflow etc.).
  - FBG uses Cloud/platform.

---

## 4. Hands-on exercises (toy sportsbook)

**Setup.** The project is at `sportsbook/`. Local DuckDB: `./run_all.sh` (seeds into landing, snapshots, builds, then Day 2). Snowflake trial from the repo root: `python snowflake/run.py setup` then `python snowflake/run.py load` (COPY into LANDING, then dbt snapshot + build). `teardown` drops everything. `python snowflake/run.py all` is setup + load and leaves objects built.

**Toy data:** 19 bets across NY/NJ/PA/MI/OH (one internal test account), 10 payments arriving in 2 batches, KYC events for 9 registrants, and VIP tier changes for 2 customers.

**Local result:** `PASS=31, WARN=0, ERROR=0`. That covers 13 models, 1 snapshot, 5 seeds, 10 data tests, 2 singular tests, and 1 unit test.

**Toy GGR conventions** (state them aloud in an interview; real FBG definitions may differ):
- *cash handle* = settled, non-void, non-bonus stakes
- *cash GGR* = cash stake − cash payout
- *bonus cost* = cash paid out on winning bonus bets (the stake isn't returned)
- *NGR* = cash GGR − bonus cost
- *Tax* uses the real headline rates from [CASPR](https://caspr.org/state-gambling-scorecard/taxes/), but the `promo_deductible_toy` flag is **illustrative except NY** (NY doesn't allow deductions). Per-wager fees, retail rates, and tiers are not modeled.

### Exercise 1: FLATTEN parlay legs from JSON, plus the "lost by one leg" mart
**Task:** Bets arrive with a JSON array of legs. Produce one row per leg. Then find settled parlays/SGPs that lost by exactly one leg and compute their combined decimal odds. This feeds bad-beat analysis, CX dispute volume, and promo eligibility.

**Snowflake answer** [Snowflake-only, NOT executed]:
```sql
-- models/silver/slv_bet_legs.sql  (Snowflake branch)
select
    b.bet_id,
    b.bet_type,
    l.index                           as leg_index,
    l.value:event::string             as event,
    l.value:market::string            as market,
    l.value:selection::string         as selection,
    l.value:american_odds::number     as american_odds,
    l.value:result::string            as leg_result
from {{ ref('brz_bets') }} b,
     lateral flatten(input => parse_json(b.legs_json)) l     -- if legs already VARIANT: input => b.legs
```
**DuckDB equivalent** [Verified on dbt-duckdb]: uses `unnest(from_json(legs_json, '["JSON"]'))` with `generate_subscripts`. The same model file switches on `{% if target.type == 'snowflake' %}`.

**Mart** [Verified on dbt-duckdb]:
```sql
-- models/gold/ops/mart_parlay_one_leg_away.sql
select b.bet_id, b.customer_id, b.state, b.bet_type, b.stake,
       count(*) as legs,
       sum(case when l.leg_result = 'lost' then 1 else 0 end) as lost_legs,
       round(exp(sum(ln({{ american_to_decimal('l.american_odds') }}))), 4) as parlay_decimal_odds  -- product via exp(sum(ln))
from {{ ref('fct_bets') }} b
join {{ ref('slv_bet_legs') }} l on l.bet_id = b.bet_id
where b.bet_type in ('parlay','sgp') and b.status = 'settled'
group by 1,2,3,4,5
having sum(case when l.leg_result = 'lost' then 1 else 0 end) = 1
```
**Verified output:**

| bet_id | customer_id | state | bet_type | stake | legs | lost_legs | parlay_decimal_odds |
|---|---|---|---|---|---|---|---|
| B02 | C1 | NY | parlay | 20 | 3 | 1 | 4.7727 |
| B12 | C6 | NY | parlay | 15 | 4 | 1 | 11.9786 |
| B18 | C2 | NJ | parlay | 40 | 3 | 1 | 5.5063 |

**Interview talking points**
- `exp(sum(ln(x)))` is the standard "product aggregate" trick.
- In real data, check **void legs**. A voided leg usually drops out of the parlay and reprices the odds, so exclude `leg_result='void'` from the product.
- Use `OUTER => TRUE` in FLATTEN if a malformed bet could have an empty legs array. Otherwise the bet silently disappears, and your handle no longer ties out.

### Exercise 2: Snapshot VIP tier (SCD2) and a point-in-time join
**Task:** VIP tier lives on the customer record and is overwritten. Keep history, then answer "what tier was the customer in *when they placed each bet*?" This matters for VIP NGR attribution and host performance.

[Verified on dbt-duckdb]
```yaml
# snapshots/snap_customer_vip.yml
snapshots:
  - name: snap_customer_vip
    relation: source('landing', 'raw_customers')
    config:
      unique_key: customer_id
      strategy: timestamp
      updated_at: updated_at
      dbt_valid_to_current: "cast('9999-12-31' as timestamp)"   # on Snowflake: "to_timestamp_ntz('9999-12-31')"
```
```sql
-- models/gold/ops/fct_bets_with_vip_tier.sql
select f.bet_id, f.customer_id, f.placed_at_utc, f.stake,
       s.vip_tier as vip_tier_at_bet, c.vip_tier as vip_tier_now
from {{ ref('fct_bets') }} f
join {{ ref('snap_customer_vip') }} s
  on s.customer_id = f.customer_id
 and f.placed_at_utc >= s.dbt_valid_from
 and f.placed_at_utc <  s.dbt_valid_to          -- half-open interval: no double-match at boundaries
join {{ ref('brz_customers') }} c on c.customer_id = f.customer_id
```
**Verified:** after the Day 2 load (C1 bronze→silver on 10/12; C3 gold→platinum on 10/11), the snapshot has two rows per changed customer:

| customer_id | vip_tier | dbt_valid_from | dbt_valid_to |
|---|---|---|---|
| C1 | bronze | 2026-10-01 13:00 | 2026-10-12 10:00 |
| C1 | silver | 2026-10-12 10:00 | 9999-12-31 |
| C3 | gold | 2026-10-02 16:00 | 2026-10-11 00:00 |
| C3 | platinum | 2026-10-11 00:00 | 9999-12-31 |

| bet_id | customer_id | placed_at_utc | stake | vip_tier_at_bet | vip_tier_now |
|---|---|---|---|---|---|
| B01 | C1 | 2026-10-09 23:00 | 100 | bronze | silver |
| B02 | C1 | 2026-10-11 16:00 | 20 | bronze | silver |
| B16 | C1 | 2026-10-14 23:00 | 80 | silver | silver |
| B05 | C3 | 2026-10-09 22:00 | 500 | gold | platinum |
| B06 | C3 | 2026-10-10 17:00 | 200 | gold | platinum |
| B15 | C3 | 2026-10-13 22:00 | 300 | platinum | platinum |

**Interview talking point:** joining on `vip_tier_now` would credit C3's pre-upgrade $700 of handle to *platinum*. That inflates the apparent impact of the VIP program, a classic bias in attribution.

### Exercise 3: Incremental MERGE for payments, and the late-arriving-data bug
**Task:** Payment statuses change (pending → completed/failed). Build `fct_payments` incrementally so updates overwrite, with no duplicates.

**First attempt** (looks right, and passes `unique`):
```sql
{{ config(materialized='incremental', incremental_strategy='merge', unique_key='payment_id') }}
select ..., case when payment_type='withdrawal' and status='completed'
                 then datediff('minute', requested_at, completed_at)/60.0 end as hours_to_withdraw
from {{ ref('brz_payments') }}
{% if is_incremental() %}
  where updated_at >= (select max(updated_at) from {{ this }})
{% endif %}
```
**What actually happened** [Verified on dbt-duckdb]:
- On the Day 2 run, P05 and P06 merged correctly (pending → completed, 12h and 48h to withdraw), and new P09 was inserted.
- **P10 was silently dropped.** P10 is a deposit whose `updated_at` (10/11 16:05) was *earlier* than the table's existing max (10/16 10:00). This is a late-arriving record, e.g., from a processor webhook replay.
- No test failed. `unique` and `not_null` both passed.

**Fix** [Verified on dbt-duckdb]: P10 appears and there are no duplicates.
```sql
{% if is_incremental() %}
  where updated_at >= (select max(updated_at) from {{ this }})
                      - interval '{{ var("payments_lookback_days", 7) }} days'
{% endif %}
```
**Snowflake notes** [NOT executed]:
- On Snowflake, write `dateadd('day', -{{ var("payments_lookback_days", 7) }}, (select max(updated_at) from {{ this }}))`.
- dbt compiles this to `MERGE INTO ... USING (tmp) ON payment_id ...`. If the source has two rows for one `payment_id` inside the window, Snowflake errors with a **nondeterministic merge**. Add `qualify row_number() over (partition by payment_id order by updated_at desc) = 1`, or use `incremental_strategy='delete+insert'`.
- A **reconciliation test** (row count by day vs source over the last N days) catches this class of bug.

**Raw Snowflake MERGE** (what dbt generates, roughly) [NOT executed]:
```sql
merge into analytics.ops.fct_payments t
using (select * from analytics.ops.fct_payments__dbt_tmp) s
on t.payment_id = s.payment_id
when matched then update set status = s.status, completed_at = s.completed_at,
                             updated_at = s.updated_at, hours_to_withdraw = s.hours_to_withdraw
when not matched then insert (payment_id, customer_id, payment_type, method, amount, status,
                              requested_at, completed_at, updated_at, hours_to_withdraw)
values (s.payment_id, s.customer_id, s.payment_type, s.method, s.amount, s.status,
        s.requested_at, s.completed_at, s.updated_at, s.hours_to_withdraw);
```
**Downstream KPI mart** (`mart_payments_daily`), verified output after the fix:

| payment_type | method | attempts | completed | success_rate_resolved | pending | median_hours_to_withdraw |
|---|---|---|---|---|---|---|
| deposit | ach | 1 | 1 | 1.00 | 0 | |
| deposit | card | 4 | 3 | 0.75 | 0 | |
| deposit | paypal | 1 | 1 | 1.00 | 0 | |
| withdrawal | ach | 1 | 1 | 1.00 | 0 | 48 |
| withdrawal | debit | 2 | 1 | 1.00 | 1 | 8 |
| withdrawal | paypal | 1 | 1 | 1.00 | 0 | 12 |

**Talking point:** "success rate" needs a stated denominator. Mine excludes pending (resolved only). A version that includes pending looks worse during peak hours.

### Exercise 4: Hold % and NGR by state mart
[Verified on dbt-duckdb]
```sql
-- models/gold/finance/mart_state_hold_ngr.sql (abridged)
with f as (select * from {{ ref('fct_bets') }} where status = 'settled'),   -- fct_bets already excludes test accounts
agg as (select state, count(*) settled_bets, sum(cash_handle) cash_handle,
               sum(cash_ggr) cash_ggr, sum(bonus_cost) bonus_cost
        from f group by state)
select a.*, round(cash_ggr / nullif(cash_handle,0), 4) as hold_pct,
       cash_ggr - bonus_cost as ngr, t.osb_tax_rate,
       case when t.promo_deductible_toy then cash_ggr - bonus_cost else cash_ggr end as taxable_base,
       round(greatest(<taxable_base>, 0) * t.osb_tax_rate, 2) as est_gaming_tax,
       ngr - est_gaming_tax as ngr_after_tax
from agg a left join {{ source('landing','state_tax_rates') }} t using (state)
```
**Verified output:**

| state | settled_bets | cash_handle | cash_ggr | hold_pct | bonus_cost | ngr | tax_rate | est_tax | ngr_after_tax |
|---|---|---|---|---|---|---|---|---|---|
| MI | 1 | 0 | 0 | *null* | 80 | −80 | 8.4% | 0 | −80 |
| NJ | 4 | 265 | 54.97 | 20.7% | 0 | 54.97 | 19.75% | 10.86 | 44.11 |
| NY | 6 | 765 | 118.33 | 15.5% | 0 | 118.33 | 51% | 60.35 | 57.98 |
| OH | 2 | 10 | 10 | 100% | 0 | 10 | 20% | 2.00 | 8.00 |
| PA | 3 | 1000 | 271.07 | 27.1% | 0 | 271.07 | 34% | 92.16 | 178.91 |

**Things to call out**
- MI hold is **null**, not 0 and not an error: the only settled MI bet was a bonus bet, so cash handle is 0 and `nullif` prevents divide-by-zero.
- NY keeps less than half its GGR because of the 51% rate.
- OH shows 100% hold on $10, which is meaningless. Show sample size next to every ratio.
- The **test account** (C7's $1,000 winning bet) is excluded upstream in `fct_bets`. Including it would have pushed NJ deeply negative.
- **Grain trap:** never compute hold from `slv_bet_legs` (leg grain). Stake would be counted once per leg. The unit test plus a `unique(bet_id)` test on `fct_bets` guard this.

### Exercise 5: Dynamic table for the live pending-withdrawals queue
**Task:** Payments Ops wants a near-real-time queue of pending withdrawals with state and VIP tier, refreshed about every 5 minutes, without an orchestrator.

```sql
-- models/gold/ops/dt_pending_withdrawals.sql
{{ config(
    materialized = 'dynamic_table' if target.type == 'snowflake' else 'view',
    target_lag = '5 minutes',
    snowflake_warehouse = 'OPS_XS_WH'
) }}
select p.payment_id, p.customer_id, c.state, c.vip_tier, p.method, p.amount, p.requested_at
from {{ ref('brz_payments') }} p
join {{ ref('brz_customers') }} c using (customer_id)
where p.payment_type = 'withdrawal' and p.status = 'pending'
```
**Status:** the Snowflake dynamic-table DDL is **NOT executed**; the query logic was **verified as a view on dbt-duckdb**. After Day 2, only P09 (C1, NY, silver, debit, $100) is pending.

**Equivalent raw DDL** [NOT executed]:
```sql
create or replace dynamic table analytics.ops.dt_pending_withdrawals
  target_lag = '5 minutes'
  warehouse  = OPS_XS_WH
  refresh_mode = auto
as
select ... ;   -- same SELECT
-- age / SLA breach computed at read time (keeps DT incrementally refreshable):
select *, datediff('second', requested_at, current_timestamp()) / 3600.0 as hours_pending
from analytics.ops.dt_pending_withdrawals
qualify hours_pending > 24 or vip_tier in ('gold','platinum');
```
**Design points**
- No `current_timestamp()` inside the DT.
- `brz_*` upstream are views. Dynamic tables can sit on views, but **not on a view that is downstream of another dynamic table**.
- Changing the SQL needs `dbt run --full-refresh -s dt_pending_withdrawals`.
- **Cost:** a 5-minute lag on an XS warehouse that never suspends adds up. Ask whether 15 minutes is good enough for a human queue.

### Exercise 6: KYC funnel with CONVERT_TIMEZONE, a dispatch macro, and a unit test
**Task:** Build the onboarding funnel by state: registered → KYC submitted → passed → FTD, plus FTD-within-24h. Report minutes-to-pass and an "auto-passed" proxy (pass within 5 min of first submit). Report dates in **ET**.

**Cross-database macro** [Snowflake branch NOT executed; DuckDB branch verified]:
```sql
{% macro to_et(col) %}{{ return(adapter.dispatch('to_et')(col)) }}{% endmacro %}
{% macro snowflake__to_et(col) %}convert_timezone('UTC', 'America/New_York', {{ col }}){% endmacro %}
{% macro default__to_et(col) %}(({{ col }} at time zone 'UTC') at time zone 'America/New_York'){% endmacro %}
```
**Model:** `fct_kyc_funnel` pivots events per customer with `min(case when event_name='...' then ts end)`, then adds the derived fields. Verified results:
- **C2 registered 10/02 02:30 UTC, which is 10/01 in ET.** A UTC-date report puts them in the wrong day.
- C2 failed KYC once, resubmitted, and passed after **750 min** (manual review). Everyone else auto-passed in 3–11 min.
- C4 deposited after more than 24h. C8 failed KYC and hasn't passed. C9 abandoned before submitting.

| state | registered | submitted | passed | FTD | FTD ≤24h | pass rate | median min to pass |
|---|---|---|---|---|---|---|---|
| MI | 1 | 1 | 1 | 1 | 0 | 1.00 | 11 |
| NJ | 1 | 1 | 1 | 1 | 1 | 1.00 | 750 |
| NY | 2 | 2 | 2 | 2 | 2 | 1.00 | 6 |
| OH | 1 | 1 | 1 | 1 | 1 | 1.00 | 6 |
| PA | 3 | 2 | 1 | 1 | 1 | 0.50 | 3 |

**Unit test** [Verified]. It mocks `brz_bets`, `brz_customers`, and the ephemeral `slv_bet_legs`. The ephemeral input must use `format: sql`; dict rows error out, which we hit and fixed.
```yaml
unit_tests:
  - name: test_fct_bets_ggr_and_bonus_logic
    model: fct_bets
    given:
      - input: ref('brz_bets')
        rows:
          - {bet_id: X1, customer_id: A, status: settled, is_bonus_bet: false, stake: 100, payout: 0, ...}
          - {bet_id: X2, customer_id: A, status: settled, is_bonus_bet: true,  stake: 50,  payout: 75, ...}
          - {bet_id: X3, customer_id: A, status: void,    is_bonus_bet: false, stake: 20,  payout: 20, ...}
          - {bet_id: X4, customer_id: T, status: settled, is_bonus_bet: false, stake: 999, payout: 0, ...}  # test acct
      - input: ref('brz_customers')
        rows: [{customer_id: A, is_test_account: false}, {customer_id: T, is_test_account: true}]
      - input: ref('slv_bet_legs')
        format: sql
        rows: |
          select 'X1' as bet_id, 0 as leg_index union all select 'X2', 0 union all select 'X3', 0
    expect:
      rows:
        - {bet_id: X1, cash_handle: 100, cash_ggr: 100, bonus_cost: 0}
        - {bet_id: X2, cash_handle: 0,   cash_ggr: 0,   bonus_cost: 75}
        - {bet_id: X3, cash_handle: 0,   cash_ggr: 0,   bonus_cost: 0}
```
**Talking point:** `DATEDIFF('minute', ...)` counts boundaries. 13:05:59 → 13:06:00 = "1 minute." For SLA tiers near the threshold, use seconds.

### Exercise 7: Metrics defined once (dbt Semantic Layer + Snowflake semantic view)
**dbt Semantic Layer YAML** [parse-validated with `dbt parse` on dbt 1.12; MetricFlow queries NOT executed]:
```yaml
semantic_models:
  - name: sem_bets
    model: ref('fct_bets')
    defaults: {agg_time_dimension: settled_date_et}
    entities:
      - {name: bet, type: primary, expr: bet_id}
      - {name: customer, type: foreign, expr: customer_id}
    dimensions:
      - {name: settled_date_et, type: time, type_params: {time_granularity: day}}
      - {name: state, type: categorical}
      - {name: bet_type, type: categorical}
    measures:
      - {name: cash_handle, agg: sum}
      - {name: cash_ggr, agg: sum}
      - {name: bonus_cost, agg: sum}
metrics:
  - {name: hold_pct, label: "Hold %", type: ratio, type_params: {numerator: cash_ggr, denominator: cash_handle}}
  - name: ngr
    type: derived
    type_params: {expr: cash_ggr - bonus_cost, metrics: [{name: cash_ggr}, {name: bonus_cost}]}
# (+ simple metrics cash_handle, cash_ggr, bonus_cost and a sem_time_spine model - see _semantic.yml)
```
**Snowflake semantic view** [Snowflake-only, NOT executed]. This is what FBG layers under Snowflake Intelligence:
```sql
create or replace semantic view analytics.ops.sem_sportsbook
  tables (
    bets as analytics.marts.fct_bets primary key (bet_id),
    customers as analytics.marts.dim_customer primary key (customer_id)
  )
  relationships ( bets_to_customers as bets(customer_id) references customers(customer_id) )
  facts ( bets.cash_handle as cash_handle, bets.cash_ggr as cash_ggr, bets.bonus_cost as bonus_cost )
  dimensions ( bets.state as state, bets.settled_date_et as settled_date_et,
               customers.vip_tier as vip_tier with synonyms = ('vip level', 'tier') )
  metrics ( bets.total_handle as sum(bets.cash_handle),
            bets.total_ggr as sum(bets.cash_ggr),
            bets.hold_pct as div0null(sum(bets.cash_ggr), sum(bets.cash_handle))
              comment = 'Cash GGR / cash handle, settled bets, test accounts excluded' );
-- query it:
select * from semantic_view(analytics.ops.sem_sportsbook
         metrics bets.hold_pct, bets.total_ggr
         dimensions bets.state);
```
**Talking point:** the `comment` and `synonyms` are not decoration. They are the context the AI agent reads, and the JD's "trusted data for agent development" means exactly this.

**Stretch ideas** (not built): `fct_cx_tickets` with `TIME_SLICE` 15-minute intervals for WFM service level; a check-strategy snapshot on RG limit settings (audit trail for limit increases); a `dbt_utils.equal_rowcount` reconciliation between `fct_payments` and the processor settlement file.

---

## 5. One-week study plan (about 1 hr/day) + sound bites

### 5.1 Resources (links checked Oct 16, 2026)
- **Snowflake free trial:** [signup.snowflake.com](https://signup.snowflake.com/). 30 days or until the free usage balance runs out; email only, no payment info ([trial docs](https://docs.snowflake.com/en/user-guide/admin-trial-account)). Snowflake's trial page advertises $400 of usage. **AI features (Cortex) are disabled on trials until you add a card.** Pick **Enterprise** edition, AWS, a US region.
- **dbt Fundamentals:** [learn.getdbt.com/courses/dbt-fundamentals](https://learn.getdbt.com/courses/dbt-fundamentals). Free; listed at roughly 5 hours, so do selected modules (below). Full catalog: [learn.getdbt.com/catalog](https://learn.getdbt.com/catalog).
- **dbt + Snowflake quickstart:** [docs.getdbt.com/guides/snowflake](https://docs.getdbt.com/guides/snowflake). It creates a free dbt platform account connected to your trial.
- **Snowflake docs used above:** [warehouses](https://docs.snowflake.com/en/user-guide/warehouses-overview), [access control](https://docs.snowflake.com/en/user-guide/security-access-control-overview), [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel), [clone](https://docs.snowflake.com/en/user-guide/object-clone), [streams](https://docs.snowflake.com/en/user-guide/streams-intro), [tasks](https://docs.snowflake.com/en/user-guide/tasks-intro), [dynamic tables](https://docs.snowflake.com/en/user-guide/dynamic-tables-about), [FLATTEN](https://docs.snowflake.com/en/sql-reference/functions/flatten), [QUALIFY](https://docs.snowflake.com/en/sql-reference/constructs/qualify), [semantic views](https://docs.snowflake.com/en/user-guide/views-semantic/overview).
- **dbt docs:** [Snowflake configs](https://docs.getdbt.com/reference/resource-configs/snowflake-configs), [incremental strategies](https://docs.getdbt.com/docs/build/incremental-strategy), [snapshots](https://docs.getdbt.com/docs/build/snapshots), [unit tests](https://docs.getdbt.com/docs/build/unit-tests), [CI](https://docs.getdbt.com/docs/deploy/continuous-integration), [Mesh](https://docs.getdbt.com/docs/mesh/about-mesh), [Semantic Layer](https://docs.getdbt.com/docs/use-dbt-semantic-layer/dbt-sl).

### 5.2 Day-by-day
| Day | ~60 min | Output |
|---|---|---|
| **Fri 10/16 (tonight, 10 min, optional)** | Sign up for the Snowflake trial so it's ready tomorrow. | Account URL saved |
| **Sat 10/17** | Section 1 (business + KPIs, 20 min). From the repo root: `python snowflake/run.py setup` (warehouse, `FBG_PREP` LANDING/BRONZE/SILVER/GOLD, roles). Run a query twice and confirm the result cache (15 min). | You can explain warehouses, credits, RBAC, and landing vs bronze aloud |
| **Sun 10/18** | dbt Fundamentals: models, sources, tests, docs modules (≈45 min at 1.25x). Then 15 min on section 3.1–3.4. | Comfortable with ref/source/tests vocabulary |
| **Mon 10/19** | `python snowflake/run.py load` — COPY into LANDING, then dbt builds `brz_`/`slv_`/`fct_`/`sem_`. Confirm Ex 1 (`LATERAL FLATTEN` in `slv_bet_legs`) and Ex 4 (hold/NGR mart) in Snowsight. | A real FLATTEN query ran in Snowflake |
| **Tue 10/20** | **Exercises 2 + 3** on Snowflake: snapshot, then the incremental bug and fix. Try Time Travel: run a bad `UPDATE`, then `CLONE ... BEFORE(STATEMENT=>...)` (60 min). | Can whiteboard SCD2 and incremental lookback |
| **Wed 10/21** | **Exercise 5** dynamic table on Snowflake (15 min). Skim the Summit write-up and JD again (15 min). Rehearse the 5 sound bites aloud plus 3 questions for Andie (30 min). | Ready |
| **Thu 10/22, 10:15–10:45 AM PT** | Re-read section 0 and the KPI list. Have a SQL scratchpad open. | Calm |

### 5.3 Five interview sound bites (Databricks → Snowflake/dbt)
1. **On the platform switch:** "The architecture is the same idea I run today, with separate storage and compute and a three-level governed namespace. What changes is mechanics. Unity Catalog grants become Snowflake roles and future grants, SQL warehouses become virtual warehouses billed per second, and Delta time travel becomes `AT`/`BEFORE` and zero-copy clones. Those clones are great for CI and for safe backfills of things like a payments fact."
2. **On metrics and AI (lead with this one):** "I've built governed metrics in Databricks Metric Views so that dashboards and Genie read one definition. That is the same pattern as your semantic views under Snowflake Intelligence. For Ops, I'd want FRT, withdrawal time, KYC pass rate, and contact rate defined once, with descriptions and synonyms, so an agent's answer matches the Sigma dashboard."
3. **On dbt quality ownership:** "My review bar on a dbt PR: grain stated and tested, `unique_key` actually unique, an incremental lookback for late-arriving events, explicit time zone, test accounts excluded, and a unit test for any revenue logic. I've seen the exact bug where a late webhook falls behind the max timestamp and silently drops from an incremental model. Uniqueness tests don't catch it, but reconciliation tests do."
4. **On modeling weight (handles the Data Vault question):** "I've implemented Data Vault and I know what it costs. Your team's move to Medallion with dbt Mesh makes sense for a fast-moving operator: certified Gold models owned centrally, and Ops consuming them through cross-project refs instead of re-deriving GGR. I'd bring DV discipline, meaning keys, history, and auditability, without the 28-hourly-models overhead."
5. **On Ops impact:** "Ops metrics are revenue metrics in disguise. Withdrawal speed and deposit approval rate drive retention and LTV. KYC time-to-pass drives FTD conversion. Bonus-abuse detection drives promo cost and NGR. And with a 51% tax in New York, every efficiency point there is worth twice as much as in a 20% state. I'd frame the team's roadmap that way."

### 5.4 Good questions for Andie
- Which Ops KPIs are most contested or least trusted today, and is there a "GGR-style" definition fight in CX or Payments?
- Does Ops Analytics own its own dbt project in the Mesh? What's the CI/review process, and who certifies metrics?
- Where are AI agents deployed in Ops today (CX deflection? KYC review triage?), and how is their performance measured against human baselines?
- How does the team split its time between stakeholder requests and foundational work, and what does a great first 90 days look like?
- How did the Sept 2 unified app (sportsbook + casino + Markets) change Ops data, e.g., CX contact drivers or KYC flows across regulated and CFTC products?

---

## Appendix: verification log
- **Executed locally:** `run_all.sh` (dbt 1.12.6, dbt-duckdb 1.11.0, DuckDB 1.5.x). Two loads; final `PASS=31 WARN=0 ERROR=0`.
- **Bugs found while building:**
  1. The late-arriving P10 was dropped by the naive incremental filter (fixed with a lookback).
  2. A unit-test mock of an ephemeral model needs `format: sql`.
  3. The hold-% range test fired on small samples (NJ −180% before more bets were added), so it was downgraded to `warn`.
- **Not executed (no Snowflake):**
  - the Snowflake branch of `slv_bet_legs` (LATERAL FLATTEN) and the `snowflake__to_et` macro
  - all `AT`/`BEFORE`/`CLONE`/`UNDROP`, stream/task, dynamic table DDL, and semantic view SQL
  - the `dynamic_table` materialization
  - MetricFlow queries (YAML parse-validated only)
- **Facts:** every company and market number above is linked to its source. FBG is private, so revenue and loss figures are executive statements or third-party estimates. Operator market shares come from aggregators of state-reported data. The Summit details come from a third-party (French) write-up of the talk, not an FBG publication.
