select
    m.dataset_id,
    m.dataset_name,
    m.workspace_id,
    w.workspace_name,
    m.configured_by_upn,
    m.is_usage_metrics_model,
    w.is_in_scope and not m.is_usage_metrics_model as is_in_scope
from {{ ref('stg_pbi__semantic_models') }} m
left join {{ ref('dim_workspaces') }} w
    on w.workspace_id = m.workspace_id
