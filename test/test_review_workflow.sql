-- Name: test_review_workflow.sql
-- Purpose: utPLSQL tests of the risk review system: candidate selection, delinquency levels, and no duplicates on rerun.
--          The four write operations with their workflow, role, and status rules are tested in Java (ReviewServiceTest / ReviewWebTest).
--          Everything is rolled back at the end, leaving no test data in the database
-- Usage: ORACLE_USER=loan_oltp scripts/run_sql.sh test/test_review_workflow.sql; then run the utPLSQL suite
-- Requires: OLTP tables, triggers, reference data, review_api, and utPLSQL deployed; the warehouse has dwd_loan_monthly_perf for R47
-- Called by: run manually
-- Note: steps expected to fail are caught with when others and their error code checked; this is a test pattern, business code never swallows errors this way

create or replace package test_review_workflow as
   --%suite(Risk review business workflow)
   --%rollback(manual)

   --%test(Candidate generation, delinquency levels, and no duplicates on rerun)
   procedure run_case;
end test_review_workflow;
/

create or replace package body test_review_workflow as
   procedure run_case is
      l_created pls_integer;
      l_existing_sample pls_integer;
      l_created_again pls_integer;
      l_created_fnm pls_integer;
      l_fnm_rows pls_integer;

      procedure check_true(in_ok in boolean, in_name in varchar2) is
         l_expectation ut_expectation;
      begin
         l_expectation := ut.expect(in_ok, in_name);
         l_expectation.to_be_true();
      end check_true;
   begin
      -- Delivered candidates may already cover sample loans; 108 is still the expected total for the fixed sample.
      select count(*) into l_existing_sample
      from review_candidate c
      where
         c.reporting_month = date '2020-06-01'
         and c.rule_version_id = 1 and c.data_source = 'FRE'
         and exists (
            select 1 from loan_dw.dwd_loan_monthly_perf p
            where
               p.release_id = 'R47'
               and p.loan_identifier = c.loan_identifier
               and p.monthly_reporting_period = c.reporting_month
         );
      -- 1. Select candidates: 2020-06 should have some, and a rerun adds none
      review_api.generate_candidates(
         'R47', date '2020-06-01', 'DLQ60_ENTRY', l_created
      );
      -- 108 is the result before the definition was moved into the dlq_level function; it must be unchanged after the rewrite
      check_true(
         l_created + l_existing_sample = 108
         , '2020-06 sample candidates total ' || (l_created + l_existing_sample)
         || ' (expected 108, including candidates already delivered)'
      );
      check_true(
         review_api.dlq_level('RA') = 99
         and review_api.dlq_level('03') = 3
         and review_api.dlq_level('00') = 0
         and review_api.dlq_level('XX') is null
         , 'dlq_level: RA -> 99, 03 -> 3, 00 -> 0, XX -> null'
      );
      review_api.generate_candidates(
         'R47', date '2020-06-01', 'DLQ60_ENTRY', l_created_again
      );
      check_true(l_created_again = 0, 'Rerun of the same month added ' || l_created_again || ' rows');

      rollback;
   end run_case;
end test_review_workflow;
/
