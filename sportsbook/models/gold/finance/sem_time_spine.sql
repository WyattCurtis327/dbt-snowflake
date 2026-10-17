{{ config(materialized='table') }}
{% if target.type == 'snowflake' %}
select dateadd('day', seq4(), '2026-01-01'::date) as date_day
from table(generator(rowcount => 365))
{% else %}
select cast(range as date) as date_day
from range(date '2026-01-01', date '2027-01-01', interval 1 day)
{% endif %}
