#!/usr/bin/env bash
# Name: 5_create_schema.sh
# Purpose: create the review accounts and every warehouse, review (OLTP), change-capture, and lineage object on a fresh database, in dependency order:
#          1. Create loan_oltp and loan_test (scripts 14 and 15) and the login-only web account loan_app
#          2. Deploy the objects below, each as its owner
#          3. Mark the database as a TEST environment (write tests refuse to run anywhere else) and grant the cross-account reads
#          4. Grow the USERS tablespace file to 8 GB if smaller (four sample vintages and the 500 MiB the candidate step keeps free), then grant and verify the web account (scripts/13_create_app_user.sh, which ends with the least-privilege test)
# Usage: scripts/5_create_schema.sh
# Requires: ODS objects created (2_create_ods.sh); passwords for loan_oltp, loan_app, and loan_test saved with python/password_store.py set
# Note: run once on a new development database; it does not upgrade an existing installation
set -euo pipefail  # stop immediately if any step fails

cd "$(dirname "$0")/.."  # repository root
container=$(.venv/bin/python python/database_target.py container)  # container name

scripts/14_create_oltp_user.sh
scripts/15_create_test_user.sh
pw=$(.venv/bin/python python/password_store.py loan_app)  # web account password from the private file
docker exec -i "$container" sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode
alter session set container = FREEPDB1;
declare
   l_count pls_integer;
begin
   select count(*) into l_count from dba_users where username = 'LOAN_APP';
   if l_count = 0 then
      execute immediate 'create user loan_app identified by "$pw"';
   end if;
   execute immediate 'grant create session to loan_app';
end;
/
exit
SQL

steps=(
  "loan_dw checks/dq_check_result.sql"
  "loan_dw checks/dq_issue.sql"
  "loan_dw checks/dq_ods_ready.sql"
  "loan_dw source/dim/dim_date.sql"
  "loan_dw source/dim/dim_geography.sql"
  "loan_dw source/dim/dim_servicer.sql"
  "loan_dw source/dim/dim_loan_key_map.sql"
  "loan_dw source/dim/dim_delinquency_status.sql"
  "loan_dw source/dim/dim_zero_balance_code.sql"
  "loan_dw source/dim/dim_loan.sql"
  "loan_dw source/dim/dim_case_status.sql"
  "loan_dw source/dim/dim_review_rule.sql"
  "loan_dw source/dim/dim_review_user.sql"
  "loan_dw source/dwd/dwd_loan_monthly_perf.sql"
  "loan_dw source/dwd/dwd_loan_monthly_perf_stage.sql"
  "loan_dw source/dwd/dwd_review_case.sql"
  "loan_dw source/dwd/dwd_review_case_event.sql"
  "loan_dw source/dwd/etl_cdc_tables.sql"
  "loan_dw source/dwd/etl_user_event_watermark.sql"
  "loan_dw source/dwd/dw_recompute_loan.sql"
  "loan_dw source/dws/dws_perf_loan_td.sql"
  "loan_dw source/dws/dws_mod_loan_td.sql"
  "loan_dw source/ads/ads_vintage_dlq60_curve.sql"
  "loan_dw source/ads/ads_dlq_transition_monthly.sql"
  "loan_dw source/ads/ads_modification_outcome.sql"
  "loan_dw source/ads/ads_release_diff.sql"
  "loan_dw source/ads/ads_review_case_monthly.sql"
  "loan_dw source/ads/ads_dlq_transition_segment.sql"
  "loan_dw source/ads/ads_vintage_dlq60_segment.sql"
  "loan_dw source/ads/ads_modification_segment.sql"
  "loan_dw source/ads/ads_cure_redefault_segment.sql"
  "loan_dw source/ads/ads_final_outcome_segment.sql"
  "loan_dw source/ops/etl_run_tables.sql"
  "loan_dw source/ops/etl_source_batch.sql"
  "loan_dw source/ops/etl_source_batch_file.sql"
  "loan_dw source/ops/dw_calculation.sql"
  "loan_dw source/ops/dw_calculation_input.sql"
  "loan_dw source/ops/dw_calculation_parent.sql"
  "loan_dw source/ops/dw_calculation_cdc.sql"
  "loan_dw source/ops/ads_history.sql"
  "loan_oltp source/oltp/oltp_tables.sql"
  "loan_oltp source/oltp/oltp_triggers.sql"
  "loan_oltp source/oltp/oltp_seed.sql"
  "loan_oltp source/oltp/candidate_delivery.sql"
  "loan_oltp source/ops/grant_oltp_to_dw.sql"
  "loan_dw source/ops/grant_dw_to_oltp.sql"
  "loan_oltp source/oltp/review_api.sql"
  "loan_oltp source/oltp/candidate_publish.sql"
  "loan_dw source/dim/load_dim_date.sql"
  "loan_dw source/dim/load_dim_delinquency_status.sql"
  "loan_dw source/dim/load_dim_geography.sql"
  "loan_dw source/dim/load_dim_loan.sql"
  "loan_dw source/dim/load_dim_review_rule.sql"
  "loan_dw source/dim/load_dim_review_user.sql"
  "loan_dw source/dim/load_dim_servicer.sql"
  "loan_dw source/dim/load_dim_zero_balance_code.sql"
  "loan_dw source/dim/v_loan_segment.sql"
  "loan_dw source/dwd/cdc_review.sql"
  "loan_dw source/dwd/find_recompute_loans.sql"
  "loan_dw source/dwd/gather_dw_stats.sql"
  "loan_dw source/dwd/load_dw_release.sql"
  "loan_dw source/dwd/load_dwd_loan_monthly_perf.sql"
  "loan_dw source/dwd/recompute_downstream_targeted.sql"
  "loan_dw source/dws/load_dws_mod_loan_td.sql"
  "loan_dw source/dws/load_dws_perf_loan_td.sql"
  "loan_dw source/ads/compare_dim_loan.sql"
  "loan_dw source/ads/compare_dwd_loan_monthly_perf.sql"
  "loan_dw source/ads/compare_releases.sql"
  "loan_dw source/ads/load_ads_cure_redefault_segment.sql"
  "loan_dw source/ads/load_ads_dlq_transition_monthly.sql"
  "loan_dw source/ads/load_ads_dlq_transition_segment.sql"
  "loan_dw source/ads/load_ads_final_outcome_segment.sql"
  "loan_dw source/ads/load_ads_modification_outcome.sql"
  "loan_dw source/ads/load_ads_modification_segment.sql"
  "loan_dw source/ads/load_ads_review_case_monthly.sql"
  "loan_dw source/ads/load_ads_vintage_dlq60_curve.sql"
  "loan_dw source/ads/load_ads_vintage_dlq60_segment.sql"
  "loan_dw source/ops/record_dw_calculation.sql"
  "loan_dw source/ops/get_ads_snapshot_calc.sql"
  "loan_dw source/rpt/rpt_views.sql"
  "loan_dw source/ops/grant_dw_to_test.sql"
  "loan_oltp source/ops/grant_oltp_to_test.sql"
)
for step in "${steps[@]}"; do  # each entry is "owner file"
  owner="${step%% *}"
  file="${step#* }"
  echo "== $owner $file"
  ORACLE_USER="$owner" scripts/run_sql.sh "$file" > /dev/null
done

scripts/run_sql.sh source/ops/database_environment.sql environment_name=TEST > /dev/null
ORACLE_USER=loan_oltp scripts/run_sql.sh source/migrate/m8_grant_status_transition.sql > /dev/null
# The candidate importer stops unless USERS has at least 500 MiB free; a new Oracle Free database starts with a small USERS file, so grow it to 8 GB, enough for the four sample vintages
docker exec -i "$container" sqlplus -s / as sysdba <<'SQL'
whenever sqlerror exit sql.sqlcode
alter session set container = FREEPDB1;
declare
   l_file varchar2(1000);
   l_bytes number;
begin
   select file_name, bytes into l_file, l_bytes from dba_data_files where tablespace_name = 'USERS';
   if l_bytes < 8589934592 then
      execute immediate 'alter database datafile ' || dbms_assert.enquote_literal(l_file) || ' resize 8g';
   end if;
end;
/
exit
SQL
scripts/13_create_app_user.sh
for owner in loan_dw loan_oltp loan_test; do  # no invalid object may remain
  ORACLE_USER="$owner" scripts/run_sql.sh checks/check_invalid_objects.sql > /dev/null
done
echo "Schema created: warehouse, review database, change capture, and lineage"
