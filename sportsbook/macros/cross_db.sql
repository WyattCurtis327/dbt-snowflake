{# Convert a UTC TIMESTAMP_NTZ to US/Eastern wall-clock time.
   Snowflake branch is what you'd write at Fanatics; duckdb branch lets us test locally. #}
{% macro to_et(col) -%}
  {{ return(adapter.dispatch('to_et')(col)) }}
{%- endmacro %}

{% macro snowflake__to_et(col) -%}
  convert_timezone('UTC', 'America/New_York', {{ col }})
{%- endmacro %}

{% macro default__to_et(col) -%}
  (({{ col }} at time zone 'UTC') at time zone 'America/New_York')
{%- endmacro %}

{% macro american_to_decimal(odds) -%}
  case when {{ odds }} > 0 then 1 + {{ odds }} / 100.0
       else 1 + 100.0 / abs({{ odds }}) end
{%- endmacro %}
