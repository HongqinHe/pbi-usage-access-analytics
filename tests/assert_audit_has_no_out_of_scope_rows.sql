-- The audit must never contain app workspaces or Usage Metrics datasets.
select a.*
from {{ ref('fct_access_usage_daily') }} a
left join {{ ref('dim_semantic_models') }} m on m.dataset_id = a.dataset_id
where a.workspace_id in (select workspace_id from {{ ref('stg_pbi__workspace_apps') }})
   or coalesce(m.is_usage_metrics_model, false)
