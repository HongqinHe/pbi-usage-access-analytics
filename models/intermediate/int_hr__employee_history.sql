{#-
  SCD Type 2 employee history built from DAILY FULL HR EXTRACTS.

  Classic "gaps and islands": a new version starts whenever an employee's
  tracked attributes change versus their previous extract. Each version gets
  valid_from / valid_to so any fact can be joined to the department the
  person was in ON THAT DAY (not their department today).

  Note: if the HR feed only gave the CURRENT state (no daily history), we
  would use a dbt snapshot instead to build this history going forward.
-#}

with extracts as (
    select
        *,
        md5(concat_ws('|', employee_name, department, job_title)) as attribute_hash
    from {{ ref('stg_hr__employee_extracts') }}
),

flagged as (
    select
        *,
        case
            when lag(attribute_hash) over (partition by employee_upn order by extract_date) is null
              or lag(attribute_hash) over (partition by employee_upn order by extract_date) <> attribute_hash
            then 1 else 0
        end as is_new_version
    from extracts
),

versioned as (
    select
        *,
        sum(is_new_version) over (
            partition by employee_upn order by extract_date
            rows between unbounded preceding and current row
        ) as version_number
    from flagged
),

versions as (
    select
        employee_upn,
        version_number,
        any_value(employee_name) as employee_name,
        any_value(department)    as department,
        any_value(job_title)     as job_title,
        min(extract_date)        as valid_from,
        max(extract_date)        as last_seen_date
    from versioned
    group by employee_upn, version_number
),

latest_extract as (
    select max(extract_date) as max_extract_date from extracts
)

select
    md5(concat_ws('|', v.employee_upn, cast(v.valid_from as varchar))) as employee_version_key,
    v.employee_upn,
    v.version_number,
    v.employee_name,
    v.department,
    v.job_title,
    v.valid_from,
    case
        when lead(v.valid_from) over (partition by v.employee_upn order by v.valid_from) is not null
            then cast(lead(v.valid_from) over (partition by v.employee_upn order by v.valid_from) - interval 1 day as date)
        when v.last_seen_date < l.max_extract_date
            then v.last_seen_date             -- left the company / dropped from feed
        else null                             -- open-ended current version
    end as valid_to,
    lead(v.valid_from) over (partition by v.employee_upn order by v.valid_from) is null
        and v.last_seen_date = l.max_extract_date as is_current
from versions v
cross join latest_extract l
