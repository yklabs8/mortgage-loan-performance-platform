#!/usr/bin/env bash
# Name: 1_create_db_user.sh
# Purpose: create the project user in FREEPDB1 and grant its privileges
# Usage: scripts/1_create_db_user.sh <user name>, for example scripts/1_create_db_user.sh loan_dw
# Requires: database started (run 0_start_db.sh first)
# Called by: run manually, only once
# Note: you type the password at run time; it is not shown on screen and never written to any file
set -euo pipefail  # stop immediately if any step fails

container="${ORACLE_CONTAINER:-oracle-db}"  # container name
user="${1:?Usage: $0 <user name>}"  # user name from the argument; error if missing
[[ "$user" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || { echo "User name may only contain letters, digits and underscores, and must start with a letter" >&2; exit 1; }
read -rs -p "Set a password for $user: " pw1; echo  # read the password without echo
read -rs -p "Enter it again: " pw2; echo  # read it a second time
[ "$pw1" = "$pw2" ] || { echo "The two passwords do not match" >&2; exit 1; }  # stop if they differ
[[ "$pw1" != *'"'* && -n "$pw1" ]] || { echo "Password must not be empty or contain double quotes" >&2; exit 1; }

# Log in with the container's internal OS authentication (no SYSTEM password needed); the password goes through stdin, never the command line
docker exec -i -e NLS_LANG=AMERICAN_AMERICA.AL32UTF8 "$container" sqlplus -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode
alter session set container = FREEPDB1;
create user $user identified by "$pw1" quota unlimited on users;
grant create session, create table, create view, create procedure, create sequence, create trigger to $user;
exit
SQL
echo "User $user created"  # success message
