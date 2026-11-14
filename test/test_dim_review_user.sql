-- Name: test_dim_review_user.sql
-- Purpose: utPLSQL checks that the current version is unique, reruns are idempotent, and reads by time work.
-- Usage: scripts/run_sql.sh test/test_dim_review_user.sql; then run utPLSQL.
-- Requires: load_dim_review_user deployed; the test rolls back at the end.

create or replace package test_dim_review_user as
   --%suite(Review user dimension SCD2)
   --%rollback(manual)

   --%test(Unique current version, no new version on rerun, readable by time)
   procedure run_case;
end test_dim_review_user;
/

create or replace package body test_dim_review_user as
   procedure run_case is
      l_user_id dim_review_user.user_id%type;
      l_old_rows pls_integer;
      l_new_rows pls_integer;
      l_role dim_review_user.role_list%type;
      l_asof_role dim_review_user.role_list%type;
      l_from timestamp(6);
      l_current_rows pls_integer;

      procedure check_true(in_ok in boolean, in_name in varchar2) is
         l_expectation ut_expectation;
      begin
         l_expectation := ut.expect(in_ok, in_name);
         l_expectation.to_be_true();
      end check_true;
   begin
      select
         user_id
         , role_list
         , valid_from
      into l_user_id, l_role, l_from
      from dim_review_user
      where username = 'analyst_demo' and is_current = 'Y';
      select count(*) into l_old_rows
      from dim_review_user
      where user_id = l_user_id;

      load_dim_review_user;
      load_dim_review_user;
      select
         count(*) as version_rows
         , count(case when is_current = 'Y' then 1 end) as current_rows
      into l_new_rows, l_current_rows
      from dim_review_user
      where user_id = l_user_id;
      check_true(
         l_new_rows = l_old_rows and l_current_rows = 1
         , 'Rerunning the same user snapshot adds no version, and there is only one current version'
      );

      select role_list into l_asof_role
      from dim_review_user
      where
         user_id = l_user_id
         and l_from >= valid_from
         and (l_from < valid_to or valid_to is null);
      check_true(l_asof_role = l_role, 'Reading by observation time returns the role at that time');
      rollback;
   end run_case;
end test_dim_review_user;
/
