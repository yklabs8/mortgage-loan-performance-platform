-- Name: e2e_review_report.sql
-- Purpose: end-to-end check of the monthly review report: print it, and fail unless it counts at least one case that was escalated and then closed.
-- Usage: scripts/run_sql.sh checks/e2e_review_report.sql
-- Requires: run_cdc_review.sql has run after the review walk-through; dq_review_cdc.sql has already reconciled the totals with OLTP
-- Called by: scripts/run_end_to_end.sh

set pagesize 100
column rule_code format a14
column current_status format a12

select
   opened_month
   , rule_code
   , current_status
   , case_count
   , escalated_count
   , closed_count
   , total_days_to_close
from ads_review_case_monthly
order by opened_month, rule_code, current_status;

declare
   l_closed number;
begin
   select coalesce(sum(closed_count), 0)
   into l_closed
   from ads_review_case_monthly
   where current_status = 'CLOSED' and escalated_count > 0;
   if l_closed = 0 then
      raise_application_error(-20044, 'The monthly review report has no escalated and closed case');
   end if;
   dbms_output.put_line('Monthly review report: ' || l_closed || ' escalated and closed case(s)');
end;
/
