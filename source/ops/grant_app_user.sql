-- Name: grant_app_user.sql
-- Purpose: loan_dw grants the web account read-only warehouse access; the OLTP side is granted separately by loan_oltp (least privilege).
--          Read: the monthly review report view rpt_review_case_monthly; the latest extraction time etl_cdc_run
--          This script grants no warehouse writes; the minimum writes on four OLTP business tables are granted by
--          source/ops/grant_oltp_to_app.sql, and the business rules live in the Java service layer.
--          Not granted: ODS, DWS, underlying ADS tables, quality tables, or any system privilege such as creating or dropping tables
-- Usage: scripts/run_sql.sh source/ops/grant_app_user.sql (loan_app is created by scripts/13_create_app_user.sh)
-- Requires: OLTP, warehouse, and report views exist
-- Called by: scripts/13_create_app_user.sh; when the web application needs a new table, add a line here and rerun (grant is safe to rerun)

-- Case evidence is read from the review database; no access to the sample DIM/DWD tables is granted.

-- Reports: the monthly review report view (not the underlying ads_review_case_monthly) and the extraction log used for "data as of"
grant select on rpt_review_case_monthly to loan_app;
grant select on etl_cdc_run to loan_app;
