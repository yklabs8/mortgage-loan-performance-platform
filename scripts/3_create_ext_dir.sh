#!/usr/bin/env bash
# 3 create ext dir.
set -euo pipefail

container="${ORACLE_CONTAINER:-oracle-db}"
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
