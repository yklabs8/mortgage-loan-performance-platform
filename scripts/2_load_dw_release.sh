#!/usr/bin/env bash
# Load the first warehouse fact path for one release after the new-layout ODS files are loaded.
set -euo pipefail

cd "$(dirname "$0")/.."
release_id="${1:?Usage: $0 release}"
scripts/run_sql.sh source/dwd/run_load_dw_release.sql "release_id=$release_id"
