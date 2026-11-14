-- Name: run_cdc_review.sql
-- Purpose: run one incremental extraction of the review system (cdc_review, 10-minute overlap window), recompute the monthly review report (load_ads_review_case_monthly), commit, and list the latest extraction runs
-- Usage: scripts/run_sql.sh source/dwd/run_cdc_review.sql
-- Requires: cdc_review and load_ads_review_case_monthly exist
-- Called by: run manually or by a scheduler

declare
   l_calc_id number;
   l_previous_ids sys.odcinumberlist;
begin
   cdc_review(10);
   -- The report and the extraction share one transaction: both update or neither does
   load_ads_review_case_monthly;
   execute immediate 'lock table dw_ads_snapshot in exclusive mode';
   select calc_id bulk collect into l_previous_ids from dw_ads_snapshot
   where output_table = 'ADS_REVIEW_CASE_MONTHLY';
   record_dw_calculation('ADS_REVIEW_CASE_MONTHLY');
   -- Under the same exclusive lock, the set difference can only be the snapshot created by this run; it does not depend on IDs being consecutive or ordered.
   select calc_id into l_calc_id from (
      select calc_id from dw_ads_snapshot
      where output_table = 'ADS_REVIEW_CASE_MONTHLY'
      minus
      select column_value from table(l_previous_ids)
   ) own_snapshot;
   commit;
   dbms_output.put_line('CDC_SNAPSHOT_ID=' || l_calc_id);
end;
/

select
   run_id
   , source_name
   , extracted_rows
   , to_char(from_ts, 'yyyy-mm-dd hh24:mi:ss') as from_ts
   , to_char(to_ts, 'yyyy-mm-dd hh24:mi:ss') as to_ts
from etl_cdc_run
order by run_id desc
fetch first 4 rows only;
