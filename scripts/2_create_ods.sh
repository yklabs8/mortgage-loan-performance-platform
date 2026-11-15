#!/usr/bin/env bash
# Name: 2_create_ods.sh; purpose: deploy ODS tables, exchange stages and the external-table loader from scratch.
# Usage: scripts/2_create_ods.sh; requires the database and platform account; called by the operator.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/3_create_ext_dir.sh
for table in ods_orig ods_perf ods_orig_pre202607 ods_perf_pre202607; do
  scripts/run_sql.sh "source/ods/$table.sql"
done
for file in source/ods/ods_exchange_stages.sql source/ods/ods_load_event.sql \
  checks/ods_file_hash.sql source/ods/ods_exchange_file.sql \
  source/ods/ext_ods_tables.sql \
  source/ods/load_ods_from_ext.sql checks/check_invalid_objects.sql; do
  scripts/run_sql.sh "$file"
done
