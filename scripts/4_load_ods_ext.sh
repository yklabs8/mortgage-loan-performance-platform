#!/usr/bin/env bash
# 4 load ods ext.
set -euo pipefail

cd "$(dirname "$0")/.."
container="${ORACLE_CONTAINER:-oracle-db}"
ext_dir=/opt/oracle/ext_data
release_id="${1:?Usage: $0 release ods_table file [--compare]}"
table="${2:?Usage: $0 release ods_table file [--compare]}"
data_file="${3:?Usage: $0 release ods_table file [--compare]}"
compare="${4:-}"

[[ "$release_id" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid release: $release_id" >&2; exit 1; }
[[ "$table" =~ ^ods_(orig|perf)$ ]] || { echo "Only ods_orig and ods_perf are supported: $table" >&2; exit 1; }
[ -f "$data_file" ] || { echo "File not found: $data_file" >&2; exit 1; }
file_name=$(basename "$data_file")
[[ "$file_name" =~ ^[A-Za-z0-9_.]+$ ]] || { echo "Invalid filename: $file_name" >&2; exit 1; }

sql_file=$(mktemp)
trap 'rm -f "$sql_file"; docker exec "$container" rm -f "$ext_dir/$file_name"' EXIT

hash_now() {
  printf "set heading off feedback off\nselect ods_file_hash('%s', '%s', '%s') from dual;\n" \
    "$table" "$release_id" "$file_name" > "$sql_file"
  scripts/run_sql.sh "$sql_file" | grep -E '^[0-9]+/[0-9]+$'
}

docker cp "$data_file" "$container:$ext_dir/$file_name"
if [ "$compare" = "--compare" ]; then
  before=$(hash_now)
  echo "Before loading: $before"
fi

printf "begin\n   load_ods_from_ext('%s', '%s', '%s');\nend;\n/\n" \
  "$release_id" "$table" "$file_name" > "$sql_file"
scripts/run_sql.sh "$sql_file"

if [ "$compare" = "--compare" ]; then
  after=$(hash_now)
  echo "After external-table loading: $after"
  if [ "$before" != "$after" ]; then
    echo "Mismatch between the two loading methods" >&2
    exit 1
  fi
  echo "Match: row counts and sums of row fingerprints agree"
fi
