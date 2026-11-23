with source as (
    select * from {{ source('raw', 'aad_group_member_snapshots') }}
)

select distinct
    cast(snapshot_date as date) as snapshot_date,
    group_id,
    group_name,
    lower(trim(member_upn))     as member_upn   -- source casing is inconsistent
from source
