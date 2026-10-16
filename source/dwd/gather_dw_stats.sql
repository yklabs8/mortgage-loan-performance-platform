-- First warehouse path; source definitions and calculations are documented in docs/metric_definitions.md.

create or replace procedure gather_dw_stats is
begin
   dbms_stats.gather_schema_stats(ownname => user, options => 'GATHER AUTO');
end gather_dw_stats;
/
