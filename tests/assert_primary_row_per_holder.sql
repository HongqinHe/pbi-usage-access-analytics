-- Exactly one primary row per day x object x user, so that
-- SUM(usage_count_deduplicated) never double counts multi-group access.
select
    activity_date, scope_level, workspace_id, dataset_id, user_upn,
    count(*) filter (where is_primary_access_row) as primary_rows
from {{ ref('fct_access_usage_daily') }}
group by all
having count(*) filter (where is_primary_access_row) <> 1
