{# EXERCISE 3: incremental MERGE on payment_id; late status updates overwrite earlier rows #}
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='payment_id',
    on_schema_change='append_new_columns'
) }}
select
    payment_id,
    customer_id,
    payment_type,
    method,
    amount,
    status,
    requested_at,
    completed_at,
    updated_at,
    case when payment_type = 'withdrawal' and status = 'completed'
         then datediff('minute', requested_at, completed_at) / 60.0 end  as hours_to_withdraw
from {{ ref('brz_payments') }}
{% if is_incremental() %}
  -- Lookback window: re-scan the last N days so LATE-ARRIVING rows (updated_at older than the
  -- current max) are still caught. MERGE on payment_id makes re-processing idempotent.
  {% if target.type == 'snowflake' %}
  where updated_at >= dateadd('day', -{{ var("payments_lookback_days", 7) }}, (select max(updated_at) from {{ this }}))
  {% else %}
  where updated_at >= (select max(updated_at) from {{ this }}) - interval '{{ var("payments_lookback_days", 7) }} days'
  {% endif %}
{% endif %}
