#!/usr/bin/env bash
# Name: 11_set_demo_passwords.sh
# Purpose: generate random web login passwords for the review system's demo users (analyst_demo, manager_demo): the database stores only BCrypt hashes,
#          and the plain text goes to app/demo-users.local.txt (not in git; open it yourself)
# Usage: scripts/11_set_demo_passwords.sh
# Requires: database started; app_user has the password_hash column
# Called by: run manually (before first using the web application; again whenever you want new passwords)
set -euo pipefail
cd "$(dirname "$0")/.."
ORACLE_USER=loan_oltp .venv/bin/python python/set_demo_passwords.py app/demo-users.local.txt
