-- Name: test_ads_review_case_monthly.sql
-- Purpose: test the monthly review report ("a loan triggers review -> assigned -> closed -> visible in the report"):
--          open two cases, escalate and close one -> incremental extraction -> recompute the report, then check:
--          1. The report's case total = warehouse case count
--          2. The closed case appears in the CLOSED row, escalated, closed count 1
--          3. The open case is in the OPEN row with 0 days to close
--          4. Recomputing once gives the same result (delete-and-insert, no doubling)
--          Everything is rolled back at the end
-- Usage: ORACLE_USER=loan_test scripts/run_sql.sh test/test_ads_review_case_monthly.sql; then run the utPLSQL suite
-- Requires: OLTP, cdc_review, load_ads_review_case_monthly deployed; the warehouse has R47
-- Called by: run manually

create or replace package test_ads_review_case_monthly as
   --%suite(Monthly review report)
   --%rollback(manual)

   --%test(Opened, assigned, and closed cases reach the report and a recompute does not double)
   procedure run_case;
end test_ads_review_case_monthly;
/

create or replace package body test_ads_review_case_monthly as
   procedure run_case is
      l_analyst loan_oltp.app_user.user_id%type;
      l_manager loan_oltp.app_user.user_id%type;
      l_created pls_integer;
      l_candidate1 loan_oltp.review_candidate.candidate_id%type;
      l_candidate2 loan_oltp.review_candidate.candidate_id%type;
      l_case1 loan_oltp.risk_review_case.case_id%type;
      l_case2 loan_oltp.risk_review_case.case_id%type;
      l_month date;
      l_ads_cases number;
      l_dw_cases number;
      l_closed number;
      l_escalated number;
      l_days number;
      l_open_cases number;
      l_open_days number;
      l_rows_before number;
      l_rows_after number;

      procedure check_true(in_ok in boolean, in_name in varchar2) is
         l_expectation ut_expectation;
      begin
         l_expectation := ut.expect(in_ok, in_name);
         l_expectation.to_be_true();
      end check_true;

   begin
      select user_id
      into l_analyst
      from loan_oltp.app_user
      where username = 'analyst_demo';
      select user_id
      into l_manager
      from loan_oltp.app_user
      where username = 'manager_demo';

      loan_oltp.review_api.generate_candidates(
         'R47', date '2020-06-01', 'DLQ60_ENTRY', l_created
      );
      select min(candidate_id)
      into l_candidate1
      from loan_oltp.review_candidate
      where
         source_release_id = 'R47' and reporting_month = date '2020-06-01'
         and loan_identifier in (
            select d.loan_identifier from loan_dw.dim_loan d
            where d.release_id = 'R47'
         );
      select min(candidate_id)
      into l_candidate2
      from loan_oltp.review_candidate
      where
         source_release_id = 'R47' and reporting_month = date '2020-06-01'
         and candidate_id > l_candidate1
         and loan_identifier in (
            select d.loan_identifier from loan_dw.dim_loan d
            where d.release_id = 'R47'
         );

      -- The direct DML below only builds CDC / report fixtures; business rules are covered by the Java tests.
      -- Case 1: assign -> note -> escalate -> close; case 2: opened only
      insert into loan_oltp.risk_review_case (
         case_number, candidate_id, opened_by_user_id, updated_by_user_id
      ) values (
         'RRC-' || lpad(loan_oltp.risk_review_case_seq.nextval, 6, '0')
         , l_candidate1, l_analyst, l_analyst
      ) returning case_id into l_case1;
      insert into loan_oltp.risk_review_case (
         case_number, candidate_id, opened_by_user_id, updated_by_user_id
      ) values (
         'RRC-' || lpad(loan_oltp.risk_review_case_seq.nextval, 6, '0')
         , l_candidate2, l_analyst, l_analyst
      ) returning case_id into l_case2;
      insert into loan_oltp.case_assignment (
         case_id, assignee_user_id, assigned_by_user_id
      ) values (l_case1, l_analyst, l_manager);
      update loan_oltp.risk_review_case
      set current_status = 'ASSIGNED', updated_by_user_id = l_manager
      where case_id = l_case1;
      insert into loan_oltp.case_annotation (
         case_id, author_user_id, note_text
      ) values (l_case1, l_analyst, 'test note');
      update loan_oltp.risk_review_case
      set current_status = 'IN_REVIEW', updated_by_user_id = l_analyst
      where case_id = l_case1;
      insert into loan_oltp.review_decision (
         case_id, decided_by_user_id, decision_type
         , decided_as_role, decision_note
      ) values (l_case1, l_manager, 'ESCALATE', 'MANAGER', 'test escalation');
      update loan_oltp.risk_review_case
      set current_status = 'ESCALATED', updated_by_user_id = l_manager
      where case_id = l_case1;
      insert into loan_oltp.review_decision (
         case_id, decided_by_user_id, decision_type
         , decided_as_role, decision_note
      ) values (l_case1, l_manager, 'CLOSE', 'MANAGER', 'test close');
      update loan_oltp.risk_review_case
      set current_status = 'CLOSED', updated_by_user_id = l_manager
      where case_id = l_case1;

      loan_dw.cdc_review(10);
      loan_dw.load_ads_review_case_monthly;

      select trunc(opened_at, 'mm')
      into l_month
      from loan_oltp.risk_review_case
      where case_id = l_case1;
      select sum(case_count)
      into l_ads_cases
      from loan_dw.ads_review_case_monthly;
      select count(*)
      into l_dw_cases
      from loan_dw.dwd_review_case;
      check_true(
         l_ads_cases = l_dw_cases
         , 'Report case total = warehouse case count (' || l_ads_cases || ')'
      );

      select
         sum(closed_count) as closed_count
         , sum(escalated_count) as escalated_count
         , sum(total_days_to_close) as total_days_to_close
      into l_closed, l_escalated, l_days
      from loan_dw.ads_review_case_monthly
      where
         opened_month = l_month and data_source = 'FRE'
         and rule_code = 'DLQ60_ENTRY' and current_status = 'CLOSED';
      check_true(l_closed >= 1 and l_escalated >= 1, 'The closed case is in the CLOSED row, escalated and closed');
      check_true(l_days >= 0, 'Days to close is not negative');

      select
         sum(case_count) as case_count
         , sum(total_days_to_close) as total_days_to_close
      into l_open_cases, l_open_days
      from loan_dw.ads_review_case_monthly
      where
         opened_month = l_month and data_source = 'FRE'
         and rule_code = 'DLQ60_ENTRY' and current_status = 'OPEN';
      check_true(
         l_open_cases >= 1 and l_open_days = 0, 'The open case is in the OPEN row with 0 days to close'
      );

      select count(*)
      into l_rows_before
      from loan_dw.ads_review_case_monthly;
      loan_dw.load_ads_review_case_monthly;
      select count(*)
      into l_rows_after
      from loan_dw.ads_review_case_monthly;
      select sum(case_count)
      into l_ads_cases
      from loan_dw.ads_review_case_monthly;
      check_true(
         l_rows_after = l_rows_before and l_ads_cases = l_dw_cases, 'Recomputing once does not double'
      );

      rollback;
      exception
         when others then
            rollback;
            raise;
   end run_case;
end test_ads_review_case_monthly;
/
