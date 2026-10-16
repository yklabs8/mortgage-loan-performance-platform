#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
container="${ORACLE_CONTAINER:-oracle-db}"
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
ORACLE_USER=loan_oltp scripts/run_sql.sh source/ops/grant_oltp_to_app.sql
echo "User $app_user is ready; scripts/12_run_app.sh starts the candidate page"
