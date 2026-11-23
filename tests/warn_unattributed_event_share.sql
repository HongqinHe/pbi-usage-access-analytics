{{ config(severity = 'warn') }}

-- DATA QUALITY MONITOR (warn, not error): share of in-scope events whose user
-- has no recorded access on that day (e.g. access granted and revoked between
-- two snapshots, admins, or a missing group snapshot). A sudden rise usually
-- means a permission snapshot or AAD feed problem.
{% set max_share = 0.02 %}

with events as (
    select
        e.*,
        exists (
            select 1
            from {{ ref('fct_access_usage_daily') }} a
            where a.activity_date = e.event_date
              and a.user_upn      = e.actor_upn
              and (
                    (e.attribution_level = 'dataset'   and a.scope_level = 'dataset'   and a.dataset_id   = e.attributed_dataset_id)
                 or (e.attribution_level = 'workspace' and a.scope_level = 'workspace' and a.workspace_id = e.workspace_id)
              )
        ) as is_attributed
    from {{ ref('fct_activity_events') }} e
)

select
    count(*)                                         as total_events,
    count(*) filter (where not is_attributed)        as unattributed_events,
    count(*) filter (where not is_attributed) * 1.0 / count(*) as unattributed_share
from events
having count(*) filter (where not is_attributed) * 1.0 / count(*) > {{ max_share }}
