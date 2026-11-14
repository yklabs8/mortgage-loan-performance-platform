-- Name: test_oltp_dw_privileges.sql
-- Purpose: check that the OLTP production package depends only on the warehouse detail and the OLTP account has none of three unneeded read privileges.
-- Usage: ORACLE_USER=loan_oltp scripts/run_sql.sh test/test_oltp_dw_privileges.sql
-- Requires: review_api compiled; revokes are run by loan_dw.

declare
   l_needed pls_integer;
   l_unused pls_integer;
   l_extra pls_integer;
begin
   select count(*) into l_needed
   from user_dependencies
   where
      name = 'REVIEW_API'
      and referenced_owner = 'LOAN_DW'
      and referenced_name = 'DWD_LOAN_MONTHLY_PERF';
   select count(*) into l_unused
   from user_dependencies
   where
      referenced_owner = 'LOAN_DW'
      and referenced_name in (
         'DIM_LOAN', 'ETL_CDC_RUN', 'RPT_REVIEW_CASE_MONTHLY'
      );
   if l_needed != 1 or l_unused != 0 then
      raise_application_error(-20082, 'review_api warehouse dependencies do not match the least-privilege design');
   end if;

   select count(*) into l_extra
   from all_tab_privs
   where
      table_schema = 'LOAN_DW'
      and grantee = 'LOAN_OLTP'
      and privilege = 'SELECT'
      and table_name in (
         'DIM_LOAN', 'ETL_CDC_RUN', 'RPT_REVIEW_CASE_MONTHLY'
      );
   if l_extra != 0 then
      raise_application_error(-20083, 'OLTP account still has unneeded warehouse read privileges: ' || l_extra);
   end if;
   dbms_output.put_line('Production package depends only on DWD_LOAN_MONTHLY_PERF; the three unneeded grants are revoked');
end;
/
