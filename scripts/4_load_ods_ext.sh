#!/usr/bin/env bash
# Name: 4_load_ods_ext.sh
# Purpose: load one new-format Freddie Mac file into ODS through an Oracle external table: copy the file into the container, run load_ods_from_ext,
#          then delete the copy. With --compare: before loading, fingerprint the existing rows of the same release and file
#          (normally loaded by python/load_ods.py), fingerprint again afterwards, and require both to match, proving the two load paths agree
# Usage: scripts/4_load_ods_ext.sh R47 ods_perf ../data/extracted/R47/sample_2026/sample_perf_2026.txt [--compare]
# Requires: database started; scripts/3_create_ext_dir.sh run; ext_ods_tables.sql, load_ods_from_ext.sql,
#!/usr/bin/env bash
# 2 load dw release.
set -euo pipefail  # stop immediately if any step fails

cd "$(dirname "$0")/.."
container=$("$(dirname "$0")/../.venv/bin/python" "$(dirname "$0")/../python/database_target.py" container)  # container name
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
