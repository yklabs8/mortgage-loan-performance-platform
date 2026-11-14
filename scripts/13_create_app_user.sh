#!/usr/bin/env bash
# Name: 13_create_app_user.sh
# Purpose: create a least-privilege database account loan_app for the review web application (the application uses its own account with only the privileges it needs):
#          1. Take the password from the user's private file; if missing, save one first with password_store.py set
#          2. Create the user as database administrator with only create session (it can log in but cannot create any table)
#          3. The warehouse and OLTP owners each grant the selects the application needs, plus inserts on the Java business tables and updates on two case columns
#          4. Run the privilege test test/test_app_user_privileges.sql (logged in as loan_app, proving it cannot drop tables or see what it should not)
# Usage: scripts/13_create_app_user.sh
# Requires: database started (0_start_db.sh); OLTP, warehouse, and report views exist
# Called by: run once on migration or fresh install; afterwards scripts/12_run_app.sh starts the application with this account
# Note: the administrator is the container's internal OS identity (no SYSTEM password needed); the password reaches the database through stdin, never on the command line
set -euo pipefail  # stop immediately if any step fails

cd "$(dirname "$0")/.."
container=$("$(dirname "$0")/../.venv/bin/python" "$(dirname "$0")/../python/database_target.py" container)  # container name
app_user="loan_app"

pw=$(.venv/bin/python python/password_store.py "$app_user")
if [[ ! "$pw" =~ ^[A-Za-z0-9_#@!%+.,:-]{12,30}$ ]]; then
  echo "Password must be 12-30 characters using letters, digits, or _#@!%+.,:-" >&2
  exit 1
fi


docker exec -i "$container" sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode
alter session set container = FREEPDB1;
declare
   l_count pls_integer;
begin
   select count(*) into l_count from dba_users where username = upper('$app_user');
   if l_count = 0 then
      execute immediate 'create user $app_user identified by "$pw"';
   else
      execute immediate 'alter user $app_user identified by "$pw"';
   end if;
   execute immediate 'grant create session to $app_user';
end;
/
exit
SQL
scripts/run_sql.sh source/ops/grant_app_user.sql
ORACLE_USER=loan_oltp scripts/run_sql.sh source/ops/grant_oltp_to_app.sql
.venv/bin/python python/check_app_privileges.py
echo "User $app_user is created and granted, and the privilege test passed; scripts/12_run_app.sh starts the application with it"
