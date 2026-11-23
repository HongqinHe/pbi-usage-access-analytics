-- SCD Type 2 employee dimension: one row per employee per version.
-- Join facts with: fact_date between valid_from and coalesce(valid_to, '9999-12-31')
select * from {{ ref('int_hr__employee_history') }}
