with source as (
    select * from {{ source('raw', 'pbi_semantic_models') }}
)

select
    dataset_id,
    workspace_id,
    dataset_name,
    lower(configured_by) as configured_by_upn,
    -- Auto-created by Power BI; would inflate scope and usage if left in.
    dataset_name ilike '{{ var("usage_metrics_dataset_pattern") }}' as is_usage_metrics_model
from source
