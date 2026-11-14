-- Name: test_review_reopen_duration.sql
-- Purpose: verify the monthly report with a counterexample closed on day 3, reopened on day 10, and closed again on day 12.
-- Usage: scripts/run_sql.sh test/test_review_reopen_duration.sql
-- Requires: DWD case and event tables, the ADS report and its load procedure; all fixtures roll back in the same transaction.

declare
   l_rule_key number;
   l_loan_key number;
   l_loan_id varchar2(12);
   l_user_id number;
   l_days number;
   l_reopened number;
begin
   select min(rule_version_key) into l_rule_key from dim_review_rule;
   select min(loan_durable_key) into l_loan_key from dim_loan_key_map;
   select loan_identifier into l_loan_id
   from dim_loan_key_map
   where loan_durable_key = l_loan_key;
   select min(user_id) into l_user_id from dim_review_user_identity;

   insert into dwd_review_case (
      case_id, case_number, candidate_id, rule_version_key, data_source
      , loan_identifier, loan_durable_key, reporting_month
      , reporting_date_key, source_release_id, current_status
      , opened_by_user_id, opened_at, opened_date_key, closed_at
      , closed_date_key, was_escalated, status_change_count
      , annotation_count, source_updated_at, was_reopened
   ) values (
      -900001, 'TEST-REOPEN', -900001, l_rule_key, 'FRE'
      , l_loan_id, l_loan_key, date '2020-06-01', 20200601
      , 'R47', 'CLOSED', l_user_id
      , timestamp '2030-01-01 00:00:00', 20300101
      , timestamp '2030-01-13 00:00:00', 20300113
      , 'N', 4, 0, systimestamp, 'Y'
   );
   insert into dwd_review_case_event (
      status_event_id, case_id, from_status, to_status
      , changed_by_user_id, changed_at, changed_date_key
   ) values (
      -900001, -900001, null, 'OPEN', l_user_id
      , timestamp '2030-01-01 00:00:00', 20300101
   );
   insert into dwd_review_case_event (
      status_event_id, case_id, from_status, to_status
      , changed_by_user_id, changed_at, changed_date_key
   ) values (
      -900002, -900001, 'OPEN', 'CLOSED', l_user_id
      , timestamp '2030-01-04 00:00:00', 20300104
   );
   insert into dwd_review_case_event (
      status_event_id, case_id, from_status, to_status
      , changed_by_user_id, changed_at, changed_date_key
   ) values (
      -900003, -900001, 'CLOSED', 'IN_REVIEW', l_user_id
      , timestamp '2030-01-11 00:00:00', 20300111
   );
   insert into dwd_review_case_event (
      status_event_id, case_id, from_status, to_status
      , changed_by_user_id, changed_at, changed_date_key
   ) values (
      -900004, -900001, 'IN_REVIEW', 'CLOSED', l_user_id
      , timestamp '2030-01-13 00:00:00', 20300113
   );

   load_ads_review_case_monthly;
   select
      total_days_to_close
      , reopened_count
   into l_days, l_reopened
   from ads_review_case_monthly
   where
      opened_month = date '2030-01-01'
      and data_source = 'FRE'
      and current_status = 'CLOSED';
   if l_days != 3 or l_reopened != 1 then
      raise_application_error(-20080, 'First close should be 3 days and the reopen flag 1');
   end if;
   rollback;
   exception
      when others then
         rollback;
         raise;
end;
/
