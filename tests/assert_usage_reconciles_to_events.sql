-- RECONCILIATION: total deduplicated usage in the audit must equal the number
-- of in-scope events that can be attributed to an access holder.
-- (Events by people with no recorded access are tracked separately by
-- warn_unattributed_event_share.)
with attributed_events as (
    select count(*) as n
    from {{ ref('fct_activity_events') }} e
    where exists (
        select 1
        from {{ ref('fct_access_usage_daily') }} a
        where a.activity_date = e.event_date
          and a.user_upn      = e.actor_upn
          and a.is_primary_access_row
          and (
                (e.attribution_level = 'dataset'   and a.scope_level = 'dataset'   and a.dataset_id   = e.attributed_dataset_id)
             or (e.attribution_level = 'workspace' and a.scope_level = 'workspace' and a.workspace_id = e.workspace_id)
          )
    )
),

audit as (
    select sum(usage_count_deduplicated) as n from {{ ref('fct_access_usage_daily') }}
)

select attributed_events.n as attributed_events, audit.n as audit_usage
from attributed_events, audit
where attributed_events.n <> audit.n
