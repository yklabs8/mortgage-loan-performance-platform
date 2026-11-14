#!/usr/bin/env bash
# Name: 15_create_test_user.sh
# Purpose: create loan_test, the account dedicated to cross-schema rollback tests; the production web application still uses the least-privilege loan_app.
# Usage: scripts/15_create_test_user.sh
# Requires: Oracle FREEPDB1 started; password saved in the user's private file.
# Called by: run once when setting up the split OLTP schema; object grants are in source/ops/grant_*_to_test.sql.
set -euo pipefail

cd "$(dirname "$0")/.."
container=$("$(dirname "$0")/../.venv/bin/python" "$(dirname "$0")/../python/database_target.py" container)
test_user="loan_test"

pw=$(.venv/bin/python python/password_store.py "$test_user")
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
   select count(*) into l_count from dba_users where username = upper('$test_user');
   if l_count = 0 then
      execute immediate 'create user $test_user identified by "$pw"';
   else
      execute immediate 'alter user $test_user identified by "$pw"';
   end if;
   execute immediate 'grant create session to $test_user';
end;
/
exit
SQL
echo "$test_user is created; the test grants are run by the two object owners separately"
