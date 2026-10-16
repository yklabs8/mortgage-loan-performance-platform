#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
container="${ORACLE_CONTAINER:-oracle-db}"
oltp_user="loan_oltp"

pw=$(.venv/bin/python python/password_store.py "$oltp_user")
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
   select count(*) into l_count from dba_users where username = upper('$oltp_user');
   if l_count = 0 then
      execute immediate 'create user $oltp_user identified by "$pw"';
   else
      execute immediate 'alter user $oltp_user identified by "$pw"';
   end if;
   execute immediate 'grant create session, create table, create sequence, create procedure to $oltp_user';
   execute immediate 'alter user $oltp_user quota 128M on USERS';
end;
/
exit
SQL
echo "$oltp_user  is ready; tables, package, and cross-schema grants are not deployed"
