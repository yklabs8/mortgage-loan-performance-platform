-- Name: grant_dw_to_test.sql
-- Purpose: minimum privileges for cross-schema rollback tests to read warehouse results and call warehouse procedures.
-- Usage: scripts/run_sql.sh source/ops/grant_dw_to_test.sql
-- Requires: loan_test and the warehouse review objects exist
-- Called by: test setup of the split OLTP schema, run by loan_dw

grant select on dim_loan to loan_test;
grant select on dwd_loan_monthly_perf to loan_test;
grant select on dim_review_rule to loan_test;
-- Only the test account reads point-in-time roles, to verify DQ011.
grant select on dim_review_user to loan_test;
grant select on dwd_review_case to loan_test;
grant select on dwd_review_case_event to loan_test;
grant select on etl_cdc_run to loan_test;
grant select on etl_watermark to loan_test;
grant select on ads_review_case_monthly to loan_test;
grant select on rpt_review_case_monthly to loan_test;
grant execute on load_dim_review_rule to loan_test;
grant execute on cdc_review to loan_test;
grant execute on load_ads_review_case_monthly to loan_test;
