-- HARD GUARD (data contract): the app-workspace exclusion depends on this
-- table. If it is empty we would silently start double-counting usage that
-- the App layer owns, so the build must fail instead.
select 'pbi_workspace_apps is empty' as failure_reason
where (select count(*) from {{ ref('stg_pbi__workspace_apps') }}) = 0
