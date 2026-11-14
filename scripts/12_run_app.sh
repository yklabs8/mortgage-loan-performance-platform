#!/usr/bin/env bash
# Name: 12_run_app.sh
# Purpose: start the review web application (app/, Spring Boot) at http://localhost:8081 ; Ctrl+C stops it
#          First builds the jar (recording the commit and whether the working tree is clean), then runs it with java -jar; the startup log and page footer show the version
#          The run log is also written to logs/review-app.log (write-operation log and error IDs are there)
# Usage: scripts/12_run_app.sh            start the web application
#        scripts/12_run_app.sh test       run only the web automated tests (mvn test; ordinary fixtures roll back, concurrency fixtures are cleaned by ID)
# Requires: database started (0_start_db.sh); Java 17, Maven; demo user passwords set (11_set_demo_passwords.sh, plain text in app/demo-users.local.txt);
#           web account loan_app created (13_create_app_user.sh); tests also need loan_test (15_create_test_user.sh)
# Called by: run manually
# Note: database passwords are read only from the user's private file,
#       placed only in this process's LOAN_DW_DB_PASSWORD, never in the repository or on the command line
#       The web application runs as the least-privilege account loan_app; tests use the dedicated loan_test: tests prepare data (temporarily change password hashes, run extractions),
#       which loan_app is not allowed to do; least privilege itself is proven by test/test_app_user_privileges.sql logging in as loan_app
set -euo pipefail  # stop immediately if any step fails

cd "$(dirname "$0")/../app"
mode="${1:-run}"  # run / test
LOAN_DW_DB_SCHEMA=LOAN_OLTP
case "$mode" in
  test)
    export LOAN_DW_TARGET="${LOAN_DW_TARGET:-TEST}"
    export LOAN_DW_REQUIRE_TEST=1
    LOAN_DW_DB_USER="loan_test" ;;  # cross-schema rollback test account
  run) LOAN_DW_DB_USER="loan_app" ;;  # the web application uses only the least-privilege account
  *) echo "Usage: $0 [run|test]" >&2; exit 1 ;;
esac
LOAN_DW_DB_DSN=$(../.venv/bin/python ../python/database_target.py dsn)
export LOAN_DW_DB_DSN
if [ "$mode" = "test" ]; then
  ../.venv/bin/python -c "import sys; sys.path.insert(0, '../python'); from db import connect_test_database; connect_test_database().close()"
fi
LOAN_DW_DB_PASSWORD=$(../.venv/bin/python ../python/password_store.py "$LOAN_DW_DB_USER")
export LOAN_DW_DB_USER LOAN_DW_DB_PASSWORD LOAN_DW_DB_SCHEMA
mvn="${MVN:-mvn}"
java="${JAVA:-java}"  # Java 17 command (replaced by a fake command in tests)

case "$mode" in
  run)
    # The log is also written to logs/review-app.log at the repository root (logs/ is not in git), rolled by Spring Boot's default size; test mode does not write this file
    LOGGING_FILE_NAME="$(cd .. && pwd)/logs/review-app.log"
    export LOGGING_FILE_NAME
    commit=$(git rev-parse HEAD)
    dirty=false
    [ -z "$(git status --porcelain)" ] || dirty=true  # uncommitted changes are still packaged, but the package is marked dirty
    "$mvn" -B -q package -DskipTests -Dgit.commit="$commit" -Dgit.dirty="$dirty"
    exec "$java" -jar "$(pwd)/target/review-app.jar" ;;  # absolute path, so other scripts can recognise this application's process
  test)
    # Only the test process uses the owner to revoke roles and hold locks in the same transaction; all fixtures roll back, and production never reads this credential.
    LOAN_DW_OLTP_PASSWORD=$(../.venv/bin/python ../python/password_store.py loan_oltp)
    LOAN_DW_APP_PASSWORD=$(../.venv/bin/python ../python/password_store.py loan_app)
    export LOAN_DW_APP_PASSWORD LOAN_DW_OLTP_PASSWORD
    exec "$mvn" -B -q test "${@:2}" ;;

esac
