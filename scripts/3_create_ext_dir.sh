#!/usr/bin/env bash
# Name: 3_create_ext_dir.sh
# Purpose: prepare a directory for external tables (Oracle reads the Freddie Mac text files directly into ODS):
#          create /opt/oracle/ext_data in the container and a directory object ODS_EXT_DIR pointing to it,
#          and grant the platform user read and write on it (read the data files; write the external-table log and bad-row files)
# Usage: scripts/3_create_ext_dir.sh (database user defaults to loan_dw)
# Requires: database started (0_start_db.sh); platform user created (1_create_db_user.sh)
#!/usr/bin/env bash
# 3 create ext dir.
set -euo pipefail  # stop immediately if any step fails

container=$("$(dirname "$0")/../.venv/bin/python" "$(dirname "$0")/../python/database_target.py" container)  # container name
db_user="${ORACLE_USER:-loan_dw}"
[[ "$db_user" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid username: $db_user" >&2; exit 1; }

docker exec "$container" mkdir -p /opt/oracle/ext_data
{
  echo "whenever sqlerror exit sql.sqlcode"
  echo "alter session set container = FREEPDB1;"
  echo "create or replace directory ods_ext_dir as '/opt/oracle/ext_data';"
  echo "grant read, write on directory ods_ext_dir to $db_user;"
  echo "exit"
} | docker exec -i "$container" sqlplus -s / as sysdba
echo "Directory ODS_EXT_DIR created; $db_user has read/write access"
