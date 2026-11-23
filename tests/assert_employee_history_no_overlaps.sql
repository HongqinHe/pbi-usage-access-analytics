-- SCD2 integrity: an employee's versions must not overlap in time,
-- and each employee has at most one current version.
with overlapping_versions as (
    select a.employee_upn, a.valid_from, b.valid_from as overlapping_valid_from
    from {{ ref('dim_employees') }} a
    join {{ ref('dim_employees') }} b
      on  a.employee_upn = b.employee_upn
      and a.employee_version_key <> b.employee_version_key
      and a.valid_from <= coalesce(b.valid_to, date '9999-12-31')
      and b.valid_from <= coalesce(a.valid_to, date '9999-12-31')
),

multiple_current as (
    select employee_upn, count(*) as n
    from {{ ref('dim_employees') }}
    where is_current
    group by employee_upn
    having count(*) > 1
)

select employee_upn, 'overlap' as issue from overlapping_versions
union all
select employee_upn, 'multiple current versions' from multiple_current
