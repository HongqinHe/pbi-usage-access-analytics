with source as (
    select * from {{ source('raw', 'pbi_access_snapshots') }}
),

renamed as (
    select
        cast(snapshot_date as date)              as snapshot_date,
        run_id,
        workspace_id,
        {{ normalize_blank('dataset_id') }}      as dataset_id,
        scope_level,
        principal_type,
        principal_id,
        case when principal_type = 'User' then lower(principal_name)
             else principal_name end              as principal_name,
        access_right,
        access_source
    from source
)

select * from renamed
-- defensive: one row per principal per object per snapshot
qualify row_number() over (
    partition by snapshot_date, workspace_id, coalesce(dataset_id, ''), scope_level, principal_id
    order by run_id desc
) = 1
