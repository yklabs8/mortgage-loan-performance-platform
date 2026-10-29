-- require_dq_ods.sql
-- Require dq ods. See docs/metric_definitions.md for analytical definitions.
declare
   l_ready pls_integer;
begin
   select count(*) into l_ready
   from dq_ods_ready_run
   where release_id = '&release_id';
   if l_ready = 0 then
      raise_application_error(-20001, 'No successful dq_ods run: &release_id');
   end if;
end;
/
