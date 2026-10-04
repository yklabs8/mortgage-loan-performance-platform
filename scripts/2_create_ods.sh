#!/usr/bin/env bash
# Name: 2_create_ods.sh
# Purpose: create the four partitioned ODS tables, their exchange staging tables, the fingerprint
#          function ods_file_hash, and the partition-exchange procedure ods_exchange_file
# Usage: scripts/2_create_ods.sh (run from the repository root)
# Requires: database started (0_start_db.sh); project user created (1_create_db_user.sh); password available as in Setup step 3 of README
# Called by: run manually, once, when deploying from scratch
set -euo pipefail  # stop immediately if any step fails

cd "$(dirname "$0")/.."  # go to the repository root; all paths below are relative to it
for table in ods_orig ods_perf ods_orig_pre202607 ods_perf_pre202607; do  # two tables for each of the two file layouts
  scripts/run_sql.sh "source/ods/$table.sql"
done
scripts/run_sql.sh source/ods/ods_exchange_stages.sql  # staging tables (load here first, swap in after checking)
scripts/run_sql.sh checks/ods_file_hash.sql  # fingerprint of one release + one source file
scripts/run_sql.sh source/ods/ods_exchange_file.sql  # check the fingerprint, then swap staging table and partition
echo "ODS objects created"  # success message
