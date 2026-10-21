{% docs project_overview %}
Fanatics-style sportsbook Medallion project. Landing (PUT/COPY or seed) →
bronze (`brz_`) → silver (`slv_`) → gold (`fct_` / `mart_` / `dt_`) →
semantic (`sem_`). Dual target: DuckDB locally, Snowflake `FBG_PREP` for
the trial and dbt Cloud.
{% enddocs %}

{% docs cash_handle %}
Settled, non-bonus stake. Open, void, and bonus bets contribute 0. This is the
denominator for hold %. Never sum `stake` from `slv_bet_legs` — that grain
double-counts handle on parlays.
{% enddocs %}

{% docs cash_ggr %}
Gross gaming revenue on cash bets: settled non-bonus stake minus payout.
Bonus, void, and open bets contribute 0. FBG centralized this definition
because Marketing, Finance, and others used to calculate GGR differently.
{% enddocs %}

{% docs bonus_cost %}
Cash paid to the customer on a winning settled bonus bet (the `payout` column).
The bonus stake itself was house money, so it is not handle and not GGR.
{% enddocs %}

{% docs ngr %}
Net gaming revenue = cash GGR minus bonus cost. Ops moves this number:
bonus abuse inflates promo cost; chargebacks and VIP churn move NGR.
{% enddocs %}

{% docs hold_pct %}
cash_ggr / cash_handle. Null when handle is 0 (bonus-only state or empty
sample). Report settled bet count next to every ratio. Tiny samples and
whale wins can push hold outside [-100%, 100%] — the singular test warns.
{% enddocs %}

{% docs landing_vs_bronze %}
Landing is PUT/COPY (Snowflake) or `dbt seed` (DuckDB). It is the first
stop after extract, not a transform layer. Bronze (`brz_*`) is 1:1 with
landing: rename, cast, lowercase. No joins and no revenue math in bronze.
{% enddocs %}

{% docs vip_scd2 %}
`raw_customers.vip_tier` is overwritten in place. `snap_customer_vip` keeps
SCD2 history (timestamp strategy on `updated_at`; current rows use
`dbt_valid_to = 9999-12-31`). Point-in-time VIP is the snapshot range join
on `placed_at_utc`. Joining only to "now" over-attributes handle to
platinum. One snapshot against current landing has no history — run
`python snowflake/run.py replay-vip` (v1 extract, then current).
`raw_vip_tier_history` is the event-sourced alternative; two changes
between snapshot runs collapse to the last tier.
{% enddocs %}

{% docs payments_lookback %}
`fct_payments` is incremental MERGE on `payment_id`. A naive
`updated_at >= max(updated_at)` filter drops late webhooks whose
`updated_at` is older than the current max. The 7-day lookback
(`payments_lookback_days`) re-scans so those rows still upsert.
{% enddocs %}
