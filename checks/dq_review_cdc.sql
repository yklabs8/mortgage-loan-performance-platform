-- Name: dq_review_cdc.sql
-- Purpose: check that cases agree between the review system (OLTP) and the warehouse: case counts, status change counts, and each case's current status;
--          the case total of the monthly review report (ads_review_case_monthly) = warehouse case count.
--          Any mismatch raises an error. Also detects deletes: OLTP has no path that deletes a case, so a direct delete would make the counts differ
-- Usage: scripts/run_sql.sh checks/dq_review_cdc.sql (run source/dwd/run_cdc_review.sql first)
-- Requires: cdc_review has run
-- Called by: run manually

declare
   l_oltp_cases pls_integer;
   l_dw_cases pls_integer;
   l_oltp_events pls_integer;
   l_dw_events pls_integer;
   l_status_diff pls_integer;
   l_ads_cases pls_integer;
begin
   select count(*)
   into l_oltp_cases
   from loan_oltp.risk_review_case;
   select count(*)
   into l_dw_cases
   from dwd_review_case;
   select count(*)
   into l_oltp_events
   from loan_oltp.case_status_history;
   select count(*)
   into l_dw_events
   from dwd_review_case_event;
   -- Cases whose current status differs (including cases in OLTP but not in the warehouse)
   select count(*)
   into l_status_diff
   from loan_oltp.risk_review_case rrc
   left join dwd_review_case drc
      on rrc.case_id = drc.case_id
   where drc.case_id is null or drc.current_status != rrc.current_status;
   select coalesce(sum(case_count), 0)
   into l_ads_cases
   from ads_review_case_monthly;

   dbms_output.put_line(
      'Cases: OLTP ' || l_oltp_cases || ', warehouse ' || l_dw_cases
      || '; status changes: OLTP ' || l_oltp_events || ', warehouse ' || l_dw_events
      || '; cases with different current status ' || l_status_diff
      || '; cases in the monthly report ' || l_ads_cases
   );
   if
   l_oltp_cases != l_dw_cases
   or l_oltp_events != l_dw_events
   or l_status_diff > 0
   or l_ads_cases != l_dw_cases
   then
      raise_application_error(-20043, 'Review system and warehouse disagree (run cdc_review once first?)');
   end if;
end;
/
