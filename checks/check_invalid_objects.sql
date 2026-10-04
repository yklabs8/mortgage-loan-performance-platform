-- Name: check_invalid_objects.sql
-- Purpose: recompile invalid objects in the current user's schema, then list
--          compilation errors and fail if any objects remain invalid
-- Usage: scripts/run_sql.sh checks/check_invalid_objects.sql (after deploying procedures)
-- Requires: none
-- Called by: deployment scripts or manually
-- Note: sqlplus may show a warning for a procedure with compilation errors without
--       returning a SQL error, so this separate check is required

-- Recompile only invalid objects (compile_all => false)
begin
   dbms_utility.compile_schema(schema => user, compile_all => false);
end;
/

select
   e.name
   , e.type
   , e.line
   , e.text
from user_errors e
where
   not exists (
      select 1
      from user_recyclebin r
      where r.object_name = e.name
   )
order by e.name, e.sequence;

declare
   l_invalid pls_integer;
begin
   select count(*)
   into l_invalid
   from user_objects o
   where
      o.status != 'VALID'
      and not exists (
         select 1
         from user_recyclebin r
         where r.object_name = o.object_name
      );
   if l_invalid > 0 then
      raise_application_error(
         -20002, l_invalid || ' objects failed to compile; see the errors above'
      );
   end if;
end;
/
