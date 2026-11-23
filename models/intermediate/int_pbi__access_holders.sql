{#-
  Expand every permission snapshot to ONE ROW PER INDIVIDUAL USER.

  Group principals are expanded with an AS-OF join to Azure AD membership:
  for a permission snapshot taken on date D we use the latest AAD snapshot
  on or before D ("who was in this group when the access was captured?").
  If no AAD snapshot exists on/before D we fall back to the earliest one.

  Grain: snapshot_date x workspace_id x dataset_id x scope_level x user_upn x group_name
  A user who holds access through two groups appears twice (once per group);
  this is handled downstream with is_primary_access_row.
-#}

with access as (
    select * from {{ ref('stg_pbi__access_snapshots') }}
),

aad as (
    select * from {{ ref('stg_aad__group_member_snapshots') }}
),

access_dates as (
    select distinct snapshot_date from access
),

aad_dates as (
    select distinct snapshot_date as aad_snapshot_date from aad
),

-- as-of mapping: permission snapshot date -> AAD snapshot date to use
access_to_aad_snapshot as (
    select
        a.snapshot_date,
        coalesce(
            max(case when g.aad_snapshot_date <= a.snapshot_date then g.aad_snapshot_date end),
            min(g.aad_snapshot_date)
        ) as aad_snapshot_date
    from access_dates a
    cross join aad_dates g
    group by a.snapshot_date
),

group_members as (
    select
        acc.snapshot_date,
        acc.run_id,
        acc.workspace_id,
        acc.dataset_id,
        acc.scope_level,
        acc.access_source,
        acc.access_right,
        aad.member_upn          as user_upn,
        acc.principal_name      as group_name,
        m.aad_snapshot_date
    from access acc
    inner join access_to_aad_snapshot m
        on acc.snapshot_date = m.snapshot_date
    inner join aad
        on  aad.snapshot_date = m.aad_snapshot_date
        and aad.group_id      = acc.principal_id
    where acc.principal_type = 'Group'
),

direct_users as (
    select
        snapshot_date,
        run_id,
        workspace_id,
        dataset_id,
        scope_level,
        access_source,
        access_right,
        principal_name          as user_upn,
        'Direct Access'         as group_name,
        cast(null as date)      as aad_snapshot_date
    from access
    where principal_type = 'User'
),

unioned as (
    select * from group_members
    union all
    select * from direct_users
)

select
    md5(concat_ws('|', cast(snapshot_date as varchar), workspace_id, coalesce(dataset_id, ''),
                  scope_level, user_upn, group_name)) as access_holder_key,
    *
from unioned
qualify row_number() over (
    partition by snapshot_date, workspace_id, coalesce(dataset_id, ''), scope_level, user_upn, group_name
    order by access_right
) = 1
