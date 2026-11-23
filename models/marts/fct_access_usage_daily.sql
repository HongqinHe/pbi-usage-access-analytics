{#-
  DATE-AWARE ACCESS x USAGE AUDIT

  Question answered for every covered day D:
    "Who had access to this model/workspace AS OF day D, and how much did
     they use it that day?"  -- including people with access but zero usage.

  Key ideas
    * Driven by activity days (a day appears if any in-scope activity exists).
    * AS-OF JOIN: day D is paired with the latest permission snapshot taken
      on or before D. If a run failed, we fall back to the previous snapshot;
      for days before snapshots began (historical backfill) we fall back to
      the earliest snapshot.
    * Department / job title are taken AS OF day D from the SCD2 HR history,
      so a person who transferred is credited to the right department.
    * Multi-group access: a person with access via two groups gets one row
      per group (to keep "which group granted access"). is_primary_access_row
      marks exactly one row per person per object per day, and
      usage_count_deduplicated is safe to SUM without double counting.

  Grain: activity_date x scope_level x workspace_id x dataset_id x user_upn x group_name
-#}

with events as (
    select * from {{ ref('fct_activity_events') }}
),

holders as (
    select * from {{ ref('int_pbi__access_holders') }}
),

app_workspaces as (
    select distinct workspace_id from {{ ref('stg_pbi__workspace_apps') }}
),

models as (
    select * from {{ ref('stg_pbi__semantic_models') }}
),

employees as (
    select * from {{ ref('int_hr__employee_history') }}
),

-- same two scope rules as the activity side
scoped_holders as (
    select h.*
    from holders h
    left join models m on h.dataset_id = m.dataset_id
    where h.workspace_id not in (select workspace_id from app_workspaces)
      and not coalesce(m.is_usage_metrics_model, false)
),

activity_days as (
    select distinct event_date as activity_date from events
),

snapshot_dates as (
    select distinct snapshot_date from scoped_holders
),

day_to_snapshot as (
    select
        d.activity_date,
        coalesce(
            max(case when s.snapshot_date <= d.activity_date then s.snapshot_date end),
            min(s.snapshot_date)
        ) as as_of_snapshot_date
    from activity_days d
    cross join snapshot_dates s
    group by d.activity_date
),

holders_by_day as (
    select
        d.activity_date,
        d.as_of_snapshot_date,
        h.workspace_id,
        h.dataset_id,
        h.scope_level,
        h.user_upn,
        h.group_name,
        h.access_source,
        h.access_right
    from day_to_snapshot d
    inner join scoped_holders h
        on h.snapshot_date = d.as_of_snapshot_date
),

dataset_usage as (
    select event_date, attributed_dataset_id as dataset_id, actor_upn, count(*) as usage_count
    from events
    where attribution_level = 'dataset'
    group by 1, 2, 3
),

workspace_usage as (
    select event_date, workspace_id, actor_upn, count(*) as usage_count
    from events
    where attribution_level = 'workspace'
    group by 1, 2, 3
),

joined as (
    select
        h.*,
        coalesce(
            case when h.scope_level = 'dataset' then du.usage_count else wu.usage_count end,
            0
        ) as usage_count
    from holders_by_day h
    left join dataset_usage du
        on  h.scope_level   = 'dataset'
        and du.event_date   = h.activity_date
        and du.dataset_id   = h.dataset_id
        and du.actor_upn    = h.user_upn
    left join workspace_usage wu
        on  h.scope_level   = 'workspace'
        and wu.event_date   = h.activity_date
        and wu.workspace_id = h.workspace_id
        and wu.actor_upn    = h.user_upn
),

final as (
    select
        md5(concat_ws('|', cast(j.activity_date as varchar), j.scope_level, j.workspace_id,
                      coalesce(j.dataset_id, ''), j.user_upn, j.group_name)) as access_usage_key,
        j.activity_date,
        j.as_of_snapshot_date,
        j.as_of_snapshot_date > j.activity_date                           as is_pre_capture_fallback,
        j.scope_level,
        j.workspace_id,
        j.dataset_id,
        j.user_upn,
        coalesce(e.employee_name, j.user_upn)                             as user_name,
        coalesce(e.department, 'Non-employee / Unknown')                  as department_as_of,
        e.job_title                                                       as job_title_as_of,
        j.group_name,
        j.access_source,
        j.access_right,
        j.usage_count,
        j.usage_count > 0                                                 as is_active,
        row_number() over (
            partition by j.activity_date, j.scope_level, j.workspace_id,
                         coalesce(j.dataset_id, ''), j.user_upn
            order by case when j.access_source = 'DatasetDirectAccess' then 0 else 1 end,
                     j.group_name
        ) = 1                                                             as is_primary_access_row
    from joined j
    left join employees e
        on  e.employee_upn = j.user_upn
        and j.activity_date between e.valid_from and coalesce(e.valid_to, date '9999-12-31')
)

select
    *,
    case when is_primary_access_row then usage_count else 0 end as usage_count_deduplicated
from final
