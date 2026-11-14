-- Name: database_environment.sql; Purpose: install a single-row database environment marker and refuse to overwrite a different environment.
-- Usage: run_sql.sh source/ops/database_environment.sql environment_name=DEMO.
-- Requires: the four platform accounts; called at installation, no business table is changed.
declare
   l_count number;
   l_environment varchar2(10);
begin
   if '&environment_name' not in ('DEMO', 'TEST', 'RESTORE') then
      raise_application_error(-20990, 'Invalid database environment');
   end if;
   select count(*) into l_count
   from user_tables
   where table_name = 'DATABASE_ENVIRONMENT';
   if l_count = 0 then
      execute immediate
         'create table database_environment ('
         || 'singleton_id number primary key check (singleton_id = 1), '
         || 'environment_name varchar2(10) not null check ('
         || 'environment_name in (''DEMO'', ''TEST'', ''RESTORE'')))';
      execute immediate
         'insert into database_environment (singleton_id, environment_name) '
         || 'values (1, :e)'
         using '&environment_name';
      commit;
   end if;
   execute immediate
      'select environment_name from database_environment' into l_environment;
   if l_environment != '&environment_name' then
      raise_application_error(-20990, 'Refuse to replace database environment');
   end if;
end;
/
grant select on database_environment to loan_oltp;
grant select on database_environment to loan_app;
grant select on database_environment to loan_test;
comment on table database_environment is 'Database environment marker; write tests are allowed only on TEST';
comment on column database_environment.singleton_id is 'Always 1, so the table has at most one row';
comment on column database_environment.environment_name is 'DEMO, TEST, or RESTORE';
