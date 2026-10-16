-- First warehouse path; source definitions and calculations are documented in docs/metric_definitions.md.

begin
   load_dw_release('&release_id');
end;
/
