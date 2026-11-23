with source as (
    select * from {{ source('raw', 'hr_employee_extracts') }}
)

select
    cast(extract_date as date)   as extract_date,
    lower(trim(employee_upn))    as employee_upn,
    employee_name,
    department,
    job_title
from source
