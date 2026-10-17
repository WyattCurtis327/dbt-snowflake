{% macro from_landing(table_name) -%}
  {%- if target.type == 'snowflake' -%}
    {{ source('landing', table_name) }}
  {%- else -%}
    {{ ref(table_name) }}
  {%- endif -%}
{%- endmacro %}
