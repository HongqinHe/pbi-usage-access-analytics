{#-
  In-scope, deduplicated, routed activity events.

  INCREMENTAL: on each run only the last few days are reprocessed
  (lookback window for late-arriving events) and merged on event_key,
  so re-runs never create duplicates (idempotent).
  `dbt build --full-refresh` rebuilds from scratch.
-#}

{{
    config(
        materialized = 'incremental',
        unique_key = 'event_key',
        incremental_strategy = 'delete+insert',
        on_schema_change = 'append_new_columns'
    )
}}

{% set lookback_days = 3 %}

select
    event_key,
    event_time_utc,
    event_date,
    workspace_id,
    dataset_id,
    report_id,
    actor_upn,
    operation,
    case
        when operation in ('ViewReport', 'ViewDashboard')      then 'View'
        when operation in ('ExportReport', 'AnalyzeInExcel')   then 'Export / Analyze'
        when operation = 'RequestCopilot'                      then 'Copilot'
        else 'External connection'
    end as operation_category,
    attribution_level,
    attributed_dataset_id,
    data_source,
    loaded_at
from {{ ref('int_pbi__activity_routed') }}

{% if is_incremental() %}
where event_date >= (
    select cast(max(event_date) - interval {{ lookback_days }} day as date) from {{ this }}
)
{% endif %}
