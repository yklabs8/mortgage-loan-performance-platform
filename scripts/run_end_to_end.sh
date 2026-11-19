#!/usr/bin/env bash
# Name: run_end_to_end.sh
# Purpose: end-to-end test on an empty database, all in Oracle:
#          1. deploy every object from scratch (warehouse, review database, change capture, lineage)
#          2. load the sample vintages through external tables, run the quality gate, verify the source batch, build every layer in PL/SQL
#          3. select review candidates with the PL/SQL procedure and publish them; a repeated run must change nothing
#          4. start the web application and walk one case through open, assign, note, escalate, close over HTTP
#          5. capture the review changes into the warehouse, reconcile them with OLTP, and recompute the monthly review report
#          6. print the space each layer uses
# Usage: LOAN_DW_TARGET=E2E scripts/run_end_to_end.sh <release> <reporting month YYYY-MM-01> <year>...
#        for example: LOAN_DW_TARGET=E2E scripts/run_end_to_end.sh R47 2009-06-01 2006 2007 2010 2015
# Requires: a new Oracle container for the target (see docs/setup.md, "End-to-end test"); passwords for loan_dw, loan_oltp, loan_app,
#           and loan_test saved with python/password_store.py; each archive extracted to ../data/extracted/<release>/sample_<year>/
#           in the July 2026 layout; LOAN_RAW_MANIFEST pointing at a manifest of those archives; Java 17 and Maven
# Note: it creates accounts and commits data, so it refuses any target other than E2E; the web application listens on port 8091
set -euo pipefail

cd "$(dirname "$0")/.."
[ "${LOAN_DW_TARGET:-}" = "E2E" ] || { echo "Set LOAN_DW_TARGET=E2E: this test deploys from scratch and commits data" >&2; exit 1; }
release="${1:?Usage: $0 <release> <reporting month> <year>...}"
month="${2:?Usage: $0 <release> <reporting month> <year>...}"
shift 2
[ "$#" -gt 0 ] || { echo "Give at least one origination year" >&2; exit 1; }
: "${LOAN_RAW_MANIFEST:?Set LOAN_RAW_MANIFEST to the manifest of the archives}"
export LOAN_RAW_MANIFEST
step() { echo "== $(date '+%H:%M:%S') $*"; }
mkdir -p logs

step "1. deploy from scratch"
scripts/0_start_db.sh
pw=$(.venv/bin/python python/password_store.py loan_dw)
printf '%s\n%s\n' "$pw" "$pw" | scripts/1_create_db_user.sh loan_dw
unset pw
scripts/2_create_ods.sh > /dev/null
scripts/5_create_schema.sh

step "2. load ${*} of $release and build the warehouse"
for year in "$@"; do
  dir="../data/extracted/$release/sample_$year"
  scripts/4_load_ods_ext.sh "$release" ods_orig "$dir/sample_orig_$year.txt" > /dev/null
  scripts/4_load_ods_ext.sh "$release" ods_perf "$dir/sample_perf_$year.txt" > /dev/null
  step "   ODS loaded: $year"
done
scripts/run_sql.sh source/ods/gather_ods_stats.sql > /dev/null
scripts/run_sql.sh checks/dq_ods.sql "release_id=$release" > /dev/null
run_id=$(.venv/bin/python python/etl_log.py start release "$release")
batch_id=$(.venv/bin/python python/lineage_batch.py begin "$release" "$run_id")
.venv/bin/python python/lineage_batch.py finish "$release" "$batch_id"
scripts/2_load_dw_release.sh "$release" > /dev/null
.venv/bin/python python/etl_log.py end "$run_id" SUCCESS

step "3. select and publish review candidates for $month"
scripts/run_sql.sh source/dim/run_load_dim_review_rule.sql > /dev/null
.venv/bin/python python/candidate_import.py "$release" "$month"
.venv/bin/python python/candidate_import.py --save-boundary logs/e2e_candidate_boundary.json
.venv/bin/python python/candidate_import.py "$release" "$month"
.venv/bin/python python/candidate_import.py --check-boundary logs/e2e_candidate_boundary.json

step "4. review one case in the web application"
scripts/11_set_demo_passwords.sh > /dev/null
SERVER_PORT=8091 scripts/12_run_app.sh > logs/e2e_app.log 2>&1 &
app_pid=$!
trap 'pkill -P "$app_pid" 2>/dev/null || true; kill "$app_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 120); do
  curl -fs -o /dev/null http://localhost:8091/login && break
  kill -0 "$app_pid" 2>/dev/null || { echo "The web application stopped; see logs/e2e_app.log" >&2; exit 1; }
  sleep 2
done
.venv/bin/python test/end_to_end_review.py http://localhost:8091 "$month"

step "5. capture review changes and rebuild the monthly review report"
scripts/run_sql.sh source/dim/run_load_dim_review_rule.sql > /dev/null
scripts/run_sql.sh source/dwd/run_cdc_review.sql > /dev/null
scripts/run_sql.sh checks/dq_review_cdc.sql
scripts/run_sql.sh checks/e2e_review_report.sql

step "6. space by layer"
scripts/run_sql.sh checks/space_by_layer.sql
ORACLE_USER=loan_oltp scripts/run_sql.sh checks/space_by_layer.sql
step "End-to-end test passed"
