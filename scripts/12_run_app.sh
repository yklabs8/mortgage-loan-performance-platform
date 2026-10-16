#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
LOAN_DW_DB_SCHEMA=LOAN_OLTP
  LOAN_DW_DB_USER="loan_app"
LOAN_DW_DB_PASSWORD=$(../.venv/bin/python ../python/password_store.py "$LOAN_DW_DB_USER")
export LOAN_DW_DB_USER LOAN_DW_DB_PASSWORD LOAN_DW_DB_SCHEMA
mvn="${MVN:-mvn}"
  exec "$mvn" -B -q spring-boot:run
