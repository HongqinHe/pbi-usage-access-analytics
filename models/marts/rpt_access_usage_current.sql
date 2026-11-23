{#-
  CURRENT-STATE access summary: everyone who holds access in the LATEST
  permission snapshot, with rolling usage counts and an adoption status.
  Feeds the "who has access but is not using it" pages of the report.

  as_of_date = latest activity date in the data (not current_date), so the
  output is reproducible.
-#}

{% set windows = var('activity_windows_days') %}

with latest as (
    select max(as_of_snapshot_date) as snapshot_date,
           max(activity_date)       as as_of_date
    from {{ ref('fct_access_usage_daily') }}
),

current_holders as (
    select distinct
        f.scope_level, f.workspace_id, f.dataset_id, f.user_upn, f.group_name,
        f.access_source, f.access_right, f.is_primary_access_row
    from {{ ref('fct_access_usage_daily') }} f
    cross join latest l
    where f.activity_date = l.as_of_date
),

usage_history as (
    select
        f.scope_level, f.workspace_id, f.dataset_id, f.user_upn, f.group_name,
        max(case when f.is_active then f.activity_date end) as last_activity_date,
        {% for w in windows %}
        sum(case when f.activity_date > l.as_of_date - interval {{ w }} day
                 then f.usage_count else 0 end)              as usage_last_{{ w }}d{{ "," if not loop.last }}
        {% endfor %}
    from {{ ref('fct_access_usage_daily') }} f
    cross join latest l
    group by 1, 2, 3, 4, 5
),

employees as (
    select * from {{ ref('int_hr__employee_history') }} where is_current
)

select
    l.as_of_date,
    l.snapshot_date,
    c.scope_level,
    c.workspace_id,
    w.workspace_name,
    c.dataset_id,
    m.dataset_name,
    c.user_upn,
    coalesce(e.employee_name, c.user_upn)              as user_name,
    coalesce(e.department, 'Non-employee / Unknown')   as department,
    c.group_name,
    c.access_source,
    c.access_right,
    c.is_primary_access_row,
    u.last_activity_date,
    {% for w in windows %}
    coalesce(u.usage_last_{{ w }}d, 0)                 as usage_last_{{ w }}d,
    {% endfor %}
    case
        when coalesce(u.usage_last_30d, 0) > 0 then 'Active (30d)'
        when u.last_activity_date is not null  then 'Dormant'
        else 'Never used'
    end                                                as adoption_status
from current_holders c
cross join latest l
left join usage_history u
    on  u.scope_level  = c.scope_level
    and u.workspace_id = c.workspace_id
    and coalesce(u.dataset_id, '') = coalesce(c.dataset_id, '')
    and u.user_upn     = c.user_upn
    and u.group_name   = c.group_name
left join {{ ref('dim_workspaces') }} w      on w.workspace_id = c.workspace_id
left join {{ ref('dim_semantic_models') }} m on m.dataset_id   = c.dataset_id
left join employees e                         on e.employee_upn = c.user_upn
