{#-
  Clean + deduplicate raw activity events.

  Dedup key = natural key (workspace_id, actor_upn, operation, event_time).
  Two alternatives were rejected:
    * the API's event_id   -> verified NOT unique (and blank in the CSV backfill)
    * the pipeline run id  -> identifies the run, not the event
  When the same event exists twice we keep the API copy over the CSV copy,
  then the earliest load.
-#}

with source as (
    select * from {{ source('raw', 'pbi_activity_events') }}
),

cleaned as (
    select
        {{ normalize_blank('event_id') }}          as api_event_id,
        cast(event_time as timestamp)              as event_time_utc,
        cast(cast(event_time as timestamp) as date) as event_date,
        workspace_id,
        {{ normalize_blank('dataset_id') }}        as dataset_id,
        {{ normalize_blank('report_id') }}         as report_id,
        lower(trim(actor_upn))                     as actor_upn,
        operation,
        data_source,
        cast(loaded_at as timestamp)               as loaded_at,
        raw_event
    from source
),

deduplicated as (
    select *
    from cleaned
    qualify row_number() over (
        partition by workspace_id, actor_upn, operation, event_time_utc
        order by case when data_source = 'API' then 0 else 1 end, loaded_at
    ) = 1
)

select
    md5(concat_ws('|', workspace_id, actor_upn, operation, cast(event_time_utc as varchar)))
        as event_key,
    *
from deduplicated
