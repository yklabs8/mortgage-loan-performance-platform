#!/usr/bin/env bash
# Name: 4_load_ods_ext.sh
# Purpose: copy the source into the Oracle container, validate and load through external tables, then remove the copy.
# Usage: scripts/4_load_ods_ext.sh release ods_table file
# Requires: scripts/2_create_ods.sh has deployed the external tables and loader.
# Called by: the operator during ODS loading.
set -euo pipefail  # stop immediately if any step fails

cd "$(dirname "$0")/.."
container=$("$(dirname "$0")/../.venv/bin/python" "$(dirname "$0")/../python/database_target.py" container)  # container name
ext_dir=/opt/oracle/ext_data
release_id="${1:?Usage: $0 release ods_table file}"
table="${2:?Usage: $0 release ods_table file}"
data_file="${3:?Usage: $0 release ods_table file}"
[ "$#" -eq 3 ] || { echo "Usage: $0 release ods_table file" >&2; exit 1; }


[[ "$release_id" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid release: $release_id" >&2; exit 1; }
[[ "$table" =~ ^ods_[a-z0-9_]+$ ]] || { echo "Invalid ODS table name: $table" >&2; exit 1; }
[ -f "$data_file" ] || { echo "File not found: $data_file" >&2; exit 1; }
file_name=$(basename "$data_file")  # Source filename (basename only)
[[ "$file_name" =~ ^[A-Za-z0-9_.]+$ ]] || { echo "Invalid filename: $file_name" >&2; exit 1; }

sql_file=$(mktemp)
trap 'rm -f "$sql_file"; docker exec "$container" rm -f "$ext_dir/$file_name"' EXIT

docker cp "$data_file" "$container:$ext_dir/$file_name"

printf "begin\n   load_ods_from_ext('%s', '%s', '%s');\nend;\n/\n" \
  "$release_id" "$table" "$file_name" > "$sql_file"
scripts/run_sql.sh "$sql_file"
