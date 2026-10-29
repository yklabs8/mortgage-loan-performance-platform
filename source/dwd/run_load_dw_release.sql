-- run_load_dw_release.sql
-- Run load dw release. See docs/metric_definitions.md for analytical definitions.
begin
   load_dw_release('&release_id');
end;
/
