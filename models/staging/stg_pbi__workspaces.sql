with source as (
    select * from {{ source('raw', 'pbi_workspaces') }}
)

select
    workspace_id,
    workspace_name,
    workspace_type,
    state as workspace_state
from source
