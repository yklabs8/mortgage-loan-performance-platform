-- Name: grant_dw_to_oltp.sql
-- Purpose: grant only the warehouse monthly detail and loan dimension that OLTP candidate selection reads; no other warehouse table is opened.
-- Usage: scripts/run_sql.sh source/ops/grant_dw_to_oltp.sql
-- Requires: user loan_oltp, dwd_loan_monthly_perf, and dim_loan exist
-- Called by: deployment of the separate OLTP schema, run by loan_dw

grant select on dwd_loan_monthly_perf to loan_oltp;
grant select on dim_loan to loan_oltp;
