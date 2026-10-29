-- run_compare_releases.sql
-- Run compare releases. See docs/metric_definitions.md for analytical definitions.
begin
   compare_releases('&old_release', '&new_release');
end;
/

select
   source_table
   , source_column
   , change_type
   , affected_rows
from ads_release_diff_summary
where
   old_release_id = '&old_release'
   and new_release_id = '&new_release'
   and affected_rows > 0
order by source_table asc, affected_rows desc;
