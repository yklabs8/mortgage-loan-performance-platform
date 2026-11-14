-- Name: test_review_cdc.sql
-- Purpose: test the incremental extraction of the review system (cdc_review):
--          1. Change one case, and the next extraction brings out only that one
--          2. Rows re-read in the overlap window are not written twice
--          3. A "late commit": timestamp earlier than the previous extraction but not yet committed at that time; with a 0-minute overlap window it is missed (proving the problem is real),
--             with 10 minutes it is read; two rows with the same timestamp are both read
--          A late commit cannot really be produced within one session, so it is simulated by writing a status history row timestamped before the previous extraction:
--          to the extraction both look the same, a row whose timestamp falls in an already-read range and that was not read before
--          Everything is rolled back at the end (OLTP test data, warehouse rows, watermarks, and extraction records return to their state before the test)
-- Usage: ORACLE_USER=loan_test scripts/run_sql.sh test/test_review_cdc.sql; then run the utPLSQL suite
-- Requires: OLTP tables and review_api, cdc_review and the warehouse tables it uses are deployed; the warehouse has R47
-- Called by: run manually

create or replace package test_review_cdc as
   --%suite(Review incremental extraction)
   --%rollback(manual)

   --%test(Watermark, overlap window, and late commits)
   procedure run_case;
end test_review_cdc;
/

create or replace package body test_review_cdc as
   procedure run_case is
      l_analyst loan_oltp.app_user.user_id%type;
      l_manager loan_oltp.app_user.user_id%type;
      l_created pls_integer;
      l_candidate1 loan_oltp.review_candidate.candidate_id%type;
      l_candidate2 loan_oltp.review_candidate.candidate_id%type;
      l_case1 loan_oltp.risk_review_case.case_id%type;
      l_case2 loan_oltp.risk_review_case.case_id%type;
      l_extracted pls_integer;
      l_rows pls_integer;
      l_status loan_dw.dwd_review_case.current_status%type;
      l_assigned_at timestamp(6);
      l_watermark timestamp(6);
      l_late_event_a number;
      l_late_event_b number;

      procedure check_true(in_ok in boolean, in_name in varchar2) is
         l_expectation ut_expectation;
      begin
         l_expectation := ut.expect(in_ok, in_name);
         l_expectation.to_be_true();
      end check_true;

      -- Rows read by the latest case extraction
      function last_case_extract return pls_integer is
         l_n pls_integer;
      begin
         select extracted_rows
         into l_n
         from loan_dw.etl_cdc_run
         where source_name = 'REVIEW_CASE'
         order by run_id desc
         fetch first 1 row only;
         return l_n;
      end last_case_extract;

      -- Whether a status history row is in the warehouse
      function event_in_dw(in_event_id in number) return boolean is
         l_n pls_integer;
      begin
         select count(*)
         into l_n
         from loan_dw.dwd_review_case_event
         where status_event_id = in_event_id;
         return l_n = 1;
      end event_in_dw;
   begin
      select user_id
      into l_analyst
      from loan_oltp.app_user
      where username = 'analyst_demo';
      select user_id
      into l_manager
      from loan_oltp.app_user
      where username = 'manager_demo';

      -- Setup: choose candidates and open two cases (direct DML only builds fixtures; the business interface that moved to Java is not called)
      loan_oltp.review_api.generate_candidates(
         'R47', date '2020-06-01', 'DLQ60_ENTRY', l_created
      );
      select min(candidate_id)
      into l_candidate1
      from loan_oltp.review_candidate
      where
         reporting_month = date '2020-06-01'
         and source_release_id = 'R47'
         and loan_identifier in (
            select d.loan_identifier from loan_dw.dim_loan d
            where d.release_id = 'R47'
         );
      select max(candidate_id)
      into l_candidate2
      from loan_oltp.review_candidate
      where
         reporting_month = date '2020-06-01'
         and source_release_id = 'R47'
         and loan_identifier in (
            select d.loan_identifier from loan_dw.dim_loan d
            where d.release_id = 'R47'
         );
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

      -- First extraction: both new cases reach the warehouse
      loan_dw.cdc_review(0);
      select count(*)
      into l_rows
      from loan_dw.dwd_review_case
      where case_id in (l_case1, l_case2);
      check_true(l_rows = 2, 'First extraction: both new cases reached the warehouse');
      with latest_runs as (
         select
            extracted_rows
            , staged_rows
            , loaded_rows
            , row_number() over (
               partition by source_name order by run_id desc
            ) as rn
         from loan_dw.etl_cdc_run
         where source_name in ('REVIEW_CASE', 'REVIEW_CASE_EVENT')
      )

      select count(*) into l_rows
      from latest_runs
      where
         rn = 1
         and staged_rows = extracted_rows
         and loaded_rows = extracted_rows;
      check_true(l_rows = 2, 'Both CDC paths recorded extraction, input, and landed key counts that agree');

      -- 1. Change only case 2 (assign) with a 0-minute overlap window: only it is extracted
      insert into loan_oltp.case_assignment (
         case_id, assignee_user_id, assigned_by_user_id
      ) values (l_case2, l_analyst, l_manager);
      update loan_oltp.risk_review_case
      set current_status = 'ASSIGNED', updated_by_user_id = l_manager
      where case_id = l_case2;
      loan_dw.cdc_review(0);
      l_extracted := last_case_extract;
      select
         current_status
         , first_assigned_at
      into l_status, l_assigned_at
      from loan_dw.dwd_review_case
      where case_id = l_case2;
      check_true(
         l_extracted = 1 and l_status = 'ASSIGNED' and l_assigned_at is not null
         , 'Changed one case, the next run extracted ' || l_extracted || ', warehouse status is now ' || l_status
      );

      -- 2. 10-minute overlap window: both cases are in the window and re-read, but not duplicated in the warehouse
      loan_dw.cdc_review(10);
      l_extracted := last_case_extract;
      select count(*)
      into l_rows
      from loan_dw.dwd_review_case
      where case_id in (l_case1, l_case2);
      check_true(
         l_extracted >= 2 and l_rows = 2
         , 'Re-read ' || l_extracted || ' cases in the overlap window; the warehouse still has only 2 rows'
      );
      select count(*)
      into l_rows
      from loan_dw.dwd_review_case_event
      where case_id in (l_case1, l_case2);
      check_true(l_rows = 3, 'No duplicated status changes: ' || l_rows || ' rows (2 openings + 1 assignment)');

      -- 3. Late commit: two status history rows with the same timestamp, both earlier than the previous extraction (simulating rows uncommitted then and committed now)
      select watermark_ts
      into l_watermark
      from loan_dw.etl_watermark
      where source_name = 'REVIEW_CASE_EVENT';
      insert into loan_oltp.case_status_history (
         case_id, from_status, to_status, changed_by_user_id, changed_at
      )
      values (
         l_case1, 'OPEN', 'OPEN', l_analyst, l_watermark - interval '1' minute
      )
      returning status_event_id into l_late_event_a;
      insert into loan_oltp.case_status_history (
         case_id, from_status, to_status, changed_by_user_id, changed_at
      )
      values (
         l_case1, 'OPEN', 'OPEN', l_analyst, l_watermark - interval '1' minute
      )
      returning status_event_id into l_late_event_b;

      loan_dw.cdc_review(0);
      check_true(
         not event_in_dw(l_late_event_a)
         , '0-minute overlap window: the late-committed change was missed (the problem is real)'
      );
      loan_dw.cdc_review(10);
      check_true(
         event_in_dw(l_late_event_a) and event_in_dw(l_late_event_b)
         , '10-minute overlap window: both late-committed rows (same timestamp) were read'
      );

      -- A reopen crosses the OLTP -> CDC boundary: the snapshot clears the close time and the events stay complete.
      insert into loan_oltp.case_annotation (
         case_id, author_user_id, note_text
      ) values (l_case2, l_analyst, 'CDC reopen test note');
      update loan_oltp.risk_review_case
      set current_status = 'IN_REVIEW', updated_by_user_id = l_analyst
      where case_id = l_case2;
      insert into loan_oltp.review_decision (
         case_id, decided_by_user_id, decision_type
         , decided_as_role, decision_note
      ) values (l_case2, l_manager, 'CLOSE', 'MANAGER', 'close first');
      update loan_oltp.risk_review_case
      set current_status = 'CLOSED', updated_by_user_id = l_manager
      where case_id = l_case2;
      loan_dw.cdc_review(10);
      insert into loan_oltp.review_decision (
         case_id, decided_by_user_id, decision_type
         , decided_as_role, decision_note
      ) values (l_case2, l_manager, 'REOPEN', 'MANAGER', 'review again');
      update loan_oltp.risk_review_case
      set current_status = 'IN_REVIEW', updated_by_user_id = l_manager
      where case_id = l_case2;
      loan_dw.cdc_review(10);
      select current_status into l_status
      from loan_dw.dwd_review_case
      where case_id = l_case2;
      select count(*) into l_rows
      from loan_dw.dwd_review_case
      where case_id = l_case2 and closed_at is null and was_reopened = 'Y';
      check_true(l_status = 'IN_REVIEW' and l_rows = 1, 'After reopening, warehouse status, close time, and reopen flag are in sync');
      select count(*) into l_rows
      from loan_dw.dwd_review_case_event
      where
         case_id = l_case2
         and from_status = 'CLOSED'
         and to_status = 'IN_REVIEW';
      check_true(l_rows = 1, 'The reopen event appears once in the warehouse');

      rollback;
   end run_case;
end test_review_cdc;
/
