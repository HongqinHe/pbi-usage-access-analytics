{#-
  The Power BI API returns '' (empty string) for a missing dataset/report id.
  Normalize to a real NULL so joins and "is null" routing behave correctly.
-#}
{% macro normalize_blank(column_name) -%}
    nullif(trim(cast({{ column_name }} as varchar)), '')
{%- endmacro %}
