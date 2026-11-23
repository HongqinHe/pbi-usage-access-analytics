with workspaces as (
    select * from {{ ref('stg_pbi__workspaces') }}
),

apps as (
    select workspace_id, count(*) as app_count
    from {{ ref('stg_pbi__workspace_apps') }}
    group by workspace_id
),

models as (
    select workspace_id, count(*) as dataset_count
    from {{ ref('stg_pbi__semantic_models') }}
    where not is_usage_metrics_model
    group by workspace_id
)

select
    w.workspace_id,
    w.workspace_name,
    w.workspace_state,
    coalesce(m.dataset_count, 0)       as dataset_count,
    coalesce(a.app_count, 0) > 0       as has_app,
    coalesce(m.dataset_count, 0) = 0   as is_report_only,
    coalesce(a.app_count, 0) = 0       as is_in_scope
from workspaces w
left join apps a   on a.workspace_id = w.workspace_id
left join models m on m.workspace_id = w.workspace_id
