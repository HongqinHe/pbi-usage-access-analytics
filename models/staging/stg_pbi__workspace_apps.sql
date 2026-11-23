with source as (
    select * from {{ source('raw', 'pbi_workspace_apps') }}
)

select
    workspace_id,
    app_id,
    app_name
from source
