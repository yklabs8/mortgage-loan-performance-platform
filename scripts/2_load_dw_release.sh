#!/usr/bin/env bash
# 2 load dw release.
set -euo pipefail

cd "$(dirname "$0")/.."
release_id="${1:?Usage: $0 release [base_release]}"
base_release_id="${2:-}"
scripts/run_sql.sh checks/require_dq_ods.sql "release_id=$release_id"

if [ -z "$base_release_id" ]; then
  scripts/run_sql.sh source/dwd/run_load_dw_release.sql "release_id=$release_id"
else
  scripts/run_sql.sh source/dwd/run_load_dw_release_targeted.sql \
    "release_id=$release_id" "base_release_id=$base_release_id"
fi
scripts/run_sql.sh checks/dq_dw.sql "release_id=$release_id"
