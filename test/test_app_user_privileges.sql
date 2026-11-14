-- Name: test_app_user_privileges.sql
-- Purpose: log in as the web account loan_app and prove it has least privilege (the application account cannot drop tables or see what it should not):
--          Allowed: read the monthly report view, the case tables, and the candidate interface; insert business records directly and update two named case columns
--          Not allowed: DROP ANY TABLE / CREATE TABLE system privileges, deleting case rows, changing other case columns or user passwords (ORA-41900 missing DELETE / UPDATE privilege),
--                       reading ODS, underlying ADS, or quality tables (ORA-00942: to it these tables "do not exist"), creating its own tables (ORA-01031)
--          Allowed writes are verified with temporary fixtures, and everything is rolled back at the end
-- Usage: ORACLE_USER=loan_app scripts/run_sql.sh test/test_app_user_privileges.sql owner=loan_dw
-- Requires: scripts/13_create_app_user.sh has run (loan_app created and granted; password read from the private file outside the repository)
-- Called by: scripts/13_create_app_user.sh

-- Unqualified table names resolve in the platform user's schema (same as the web connection settings, see application.yml)
alter session set current_schema = &owner;

declare
   l_count number;
   l_failed pls_integer := 0;
   l_candidate number;
   l_case number;
   l_user number;
   l_state varchar2(20);

   procedure check_true(in_ok in boolean, in_name in varchar2) is
   begin
      if in_ok then
         dbms_output.put_line('PASS: ' || in_name);
      else
         dbms_output.put_line('FAIL: ' || in_name);
         l_failed := l_failed + 1;
      end if;
   end check_true;

   -- Run one statement and return its error code (0 = success); used only for the fixed test statements below, never external input
   function try_sql(in_sql in varchar2) return number is
   begin
      execute immediate in_sql;
      return 0;
      exception
         when others then
            return sqlcode;
   end try_sql;

begin
   check_true(user = 'LOAN_APP', 'Logged in as LOAN_APP (' || user || ')');

   -- Allowed
   select count(*)
   into l_count
   from loan_dw.rpt_review_case_monthly;
   check_true(true, 'Can read the monthly review report view');
   select count(*)
   into l_count
   from risk_review_case;
   check_true(true, 'Can read the case table');
   check_true(
      try_sql(
         'declare n number; begin review_api.generate_candidates('
         || '''R47'', date ''2020-06-01'', ''DLQ60_ENTRY'', n); end;'
      ) = -6550
      , 'The web account cannot run the candidate reference procedure'
   );
   check_true(
      try_sql('select count(*) from loan_dw.dim_loan') = -942
      , 'The web account cannot read the sample loan dimension'
   );
   check_true(
      try_sql('select count(*) from loan_dw.dwd_loan_monthly_perf') = -942
      , 'The web account cannot read the sample monthly detail'
   );
   select count(*) into l_count from review_evidence;
   check_true(true, 'The web account can read evidence');
   select count(*) into l_count from review_evidence_month;
   check_true(true, 'The web account can read monthly evidence');
   check_true(
      try_sql('delete from review_evidence where 1=0') in (-41900, -1031)
      , 'The web account cannot write evidence'
   );
   check_true(
      try_sql('delete from review_evidence_month where 1=0')
      in (-41900, -1031), 'The web account cannot write monthly evidence'
   );
   l_candidate := &candidate_id;
   select min(user_id) into l_user from app_user;
   insert into risk_review_case (
      case_number, candidate_id, current_status
      , opened_by_user_id, updated_by_user_id
   ) values (
      'RRC-' || lpad(risk_review_case_seq.nextval, 6, '0')
      , l_candidate, 'OPEN', l_user, l_user
   ) returning case_id into l_case;
   insert into case_annotation (case_id, author_user_id, note_text)
   values (l_case, l_user, 'least-privilege rollback fixture');
   select count(*) into l_count from case_annotation
   where case_id = l_case;
   check_true(l_count = 1, 'Can insert a note directly');
   update risk_review_case
   set current_status = 'ASSIGNED', updated_by_user_id = l_user
   where case_id = l_case;
   select current_status into l_state from risk_review_case
   where case_id = l_case;
   check_true(l_state = 'ASSIGNED', 'Can update case status and the acting user');
   check_true(
      try_sql('update risk_review_case set candidate_id = candidate_id')
      in (-41900, -1031)
      , 'Cannot update candidate_id'
   );
   check_true(
      try_sql(
         'insert into case_status_history (case_id, to_status) '
         || 'values (' || l_case || ', ''OPEN'')'
      ) in (-41900, -1031
      )
      , 'Cannot write status history directly'
   );

   -- Only loan_test may read the full user history dimension; the web account still cannot.
   check_true(
      try_sql('select count(*) from loan_dw.dim_review_user') = -942
      , 'The web account cannot read the user history dimension (ORA-00942)'
   );

   -- Not allowed
   -- drop / create are never really run: with a wrong grant, the DDL would commit implicitly and damage business tables or leave junk tables.
   -- Oracle has no object privilege "allow another user to drop this table"; a non-owner can drop only with DROP ANY TABLE.
   select count(*)
   into l_count
   from session_privs
   where privilege = 'DROP ANY TABLE';
   check_true(l_count = 0, 'No DROP ANY TABLE, so the case table cannot be dropped');
   -- Insert/update/delete on readable but not writable tables: from Oracle 23ai the more specific ORA-41900 (missing DELETE / UPDATE privilege) is raised,
   -- earlier versions raise ORA-01031; both count as "blocked"
   check_true(
      try_sql('delete from risk_review_case') in (-41900, -1031)
      , 'Cannot delete case rows directly (ORA-41900)'
   );
   -- Password hash and lockout columns can change (self-service password change); user name and active status cannot
   check_true(
      try_sql('update app_user set is_active = is_active') in (-41900, -1031)
      , 'Cannot change a user''s active status (ORA-41900)'
   );
   check_true(
      try_sql('update app_user set username = username') in (-41900, -1031)
      , 'Cannot change a user name (ORA-41900)'
   );
   check_true(
      try_sql('select count(*) from ods_perf') = -942, 'Cannot see ODS (ORA-00942)'
   );
   check_true(
      try_sql('select count(*) from ads_review_case_monthly') = -942
      , 'Cannot see the report''s underlying table, only the view (ORA-00942)'
   );
   check_true(
      try_sql('select count(*) from dq_check_result') = -942
      , 'Cannot see quality check results (ORA-00942)'
   );
   select count(*)
   into l_count
   from session_privs
   where privilege = 'CREATE TABLE';
   check_true(l_count = 0, 'No CREATE TABLE, so it cannot create tables');

   rollback;
   if l_failed > 0 then
      raise_application_error(-20046, l_failed || ' checks failed');
   end if;
   dbms_output.put_line('All passed');
   exception
      when others then
         rollback;
         raise;
end;
/
