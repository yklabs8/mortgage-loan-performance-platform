#!/usr/bin/env bash
# Name: run_sql.sh
# Purpose: run one SQL file as the project user on the Oracle database (FREEPDB1) in Docker
# Usage: scripts/run_sql.sh <SQL file> [name=value ...]
#        for example scripts/run_sql.sh source/ods/ods_orig.sql
#        each "name=value" becomes a sqlplus substitution variable, referenced as &name in the SQL file
# Requires: database started (0_start_db.sh)
# Password source, in order: environment variable ORACLE_PASSWORD; if not set, the macOS Keychain (service loan-dw-oracle); otherwise a prompt in the terminal
# Called by: run manually, or by other scripts
# Note: the password is passed to the database through stdin; it is never shown, written to a file, or put on the command line
set -euo pipefail  # stop immediately if any step fails

container="${ORACLE_CONTAINER:-oracle-db}"  # container name
db_user="${ORACLE_USER:-loan_dw}"  # database user name
sql_file="${1:?Usage: $0 <SQL file> [name=value ...]}"  # the SQL file to run; error if missing
[ -f "$sql_file" ] || { echo "File not found: $sql_file" >&2; exit 1; }  # stop if the file does not exist
shift  # the remaining arguments are all "name=value"
for kv in "$@"; do  # check each argument's format so nothing else slips into the SQL
  [[ "$kv" =~ ^[a-z_]+=[A-Za-z0-9_]+$ ]] || { echo "Bad argument format: $kv" >&2; exit 1; }
done
if [ -n "${ORACLE_PASSWORD:-}" ]; then  # 1. environment variable
  pw="$ORACLE_PASSWORD"
elif command -v security >/dev/null 2>&1; then  # 2. macOS Keychain
  pw=$(security find-generic-password -a "$db_user" -s loan-dw-oracle -w)
else  # 3. typed in the terminal, without echo
  read -rs -p "Database password for $db_user: " pw; echo >&2
fi

{  # the lines below are concatenated and passed to sqlplus together
  echo "whenever sqlerror exit sql.sqlcode"  # exit at the first SQL error and return its code
  echo "connect $db_user/\"$pw\"@//localhost:1521/FREEPDB1"  # log in (this line is not displayed)
  echo "set verify off"  # do not show substitution-variable replacement
  echo "set sqlblanklines on"  # allow blank lines inside a statement (otherwise a blank line ends the statement)
  echo "set pagesize 200 linesize 200 tab off"  # output layout: 200 lines per page, 200 characters per line
  echo "set serveroutput on"  # show what procedures and tests print with dbms_output
  for kv in "$@"; do echo "define ${kv%%=*} = ${kv#*=}"; done  # define substitution variables
  cat "$sql_file"  # the SQL file itself
  echo "exit"  # exit when done
} | docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$container" sqlplus -s /nolog  # run sqlplus inside the container
# NLS_LANG must be UTF-8: without it, non-ASCII text written to the database silently becomes the replacement character \FFFD, with no error (tested 2026-09-25)
