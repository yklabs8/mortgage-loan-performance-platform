-- Name: run_utplsql.sql
-- Purpose: run a deployed utPLSQL suite; a missing suite, no tests, or a failed assertion makes SQL*Plus exit with an error.
-- Usage: scripts/run_sql.sh test/run_utplsql.sql suite_name=test_review_cdc
-- Requires: utPLSQL, and the suite package deployed in the current user's schema
-- Called by: run manually

begin
   if not ut_runner.is_suite(user, upper('&suite_name')) then
      raise_application_error(-20071, 'utPLSQL suite not found: ' || '&suite_name');
   end if;
   if not ut_runner.is_test(user, upper('&suite_name'), 'RUN_CASE') then
      raise_application_error(-20072, 'The suite has no RUN_CASE test: ' || '&suite_name');
   end if;
   ut_runner.run(
      ut_varchar2_list(upper('&suite_name'))
      , ut_reporters(ut_documentation_reporter())
      , a_fail_on_errors => true
   );
   dbms_output.put_line('utPLSQL passed: ' || '&suite_name');
end;
/
