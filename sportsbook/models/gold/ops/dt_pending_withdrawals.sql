{# EXERCISE 5: dynamic table on Snowflake (auto-refresh every 5 min); plain view elsewhere.
   No CURRENT_TIMESTAMP inside the DT -> keeps it eligible for incremental refresh;
   compute "age" in the BI layer / a view on top. #}
{{ config(
    materialized = 'dynamic_table' if target.type == 'snowflake' else 'view',
    target_lag = '5 minutes',
    snowflake_warehouse = 'OPS_XS_WH'
) }}
select
    p.payment_id,
    p.customer_id,
    c.state,
    c.vip_tier,
    p.method,
    p.amount,
    p.requested_at
from {{ ref('brz_payments') }} p
join {{ ref('brz_customers') }} c using (customer_id)
where p.payment_type = 'withdrawal'
  and p.status = 'pending'
