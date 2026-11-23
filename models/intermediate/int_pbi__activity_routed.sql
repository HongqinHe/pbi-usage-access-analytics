{#-
  Apply the two business scope rules and route each event to exactly one
  attribution branch.

  Scope rules (consumption-layer only; raw stays complete):
    1. Drop workspaces that publish a Power BI App (owned by the App layer).
    2. Drop events on auto-created "Usage Metrics" datasets.

  Routing question: "Is (workspace_id, dataset_id) one of OUR in-scope models
  in THIS workspace?"
    yes -> attribution_level = 'dataset'   (credited to that model's access holders)
    no  -> attribution_level = 'workspace' (credited via workspace membership)
  This correctly routes report-only workspaces whose reports point at a model
  that lives in another workspace, plus dataset-less operations such as
  RequestCopilot / ConnectFromExternalApplication.
-#}

with events as (
    select * from {{ ref('stg_pbi__activity_events') }}
),

app_workspaces as (
    select distinct workspace_id from {{ ref('stg_pbi__workspace_apps') }}
),

models as (
    select * from {{ ref('stg_pbi__semantic_models') }}
),

our_models as (
    select workspace_id, dataset_id
    from models
    where not is_usage_metrics_model
)

select
    e.event_key,
    e.event_time_utc,
    e.event_date,
    e.workspace_id,
    e.dataset_id,
    e.report_id,
    e.actor_upn,
    e.operation,
    e.data_source,
    e.loaded_at,
    case when om.dataset_id is not null then 'dataset' else 'workspace' end as attribution_level,
    om.dataset_id                                                            as attributed_dataset_id
from events e
left join models m
    on e.dataset_id = m.dataset_id
left join our_models om
    on  e.workspace_id = om.workspace_id
    and e.dataset_id   = om.dataset_id
where e.workspace_id not in (select workspace_id from app_workspaces)
  and not coalesce(m.is_usage_metrics_model, false)
