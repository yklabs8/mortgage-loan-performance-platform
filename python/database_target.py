"""Single place for the database target, connection address, and the TEST-only guard for write tests.

Usage: LOAN_DW_TARGET=TEST (or E2E, the database the end-to-end test deploys from empty); default DEMO. Shared by shell, Python, and the web application.
"""

import os

TARGETS = {
    "DEMO": ("oracle-db", "localhost:1521/FREEPDB1"),
    "TEST": ("oracle-test", "localhost:1522/FREEPDB1"),
    "RESTORE": ("oracle-restore", "localhost:1523/FREEPDB1"),
    "E2E": ("oracle-e2e", "localhost:1524/FREEPDB1"),
}


def settings():
    target = os.environ.get("LOAN_DW_TARGET", "DEMO").upper()
    if target not in TARGETS:
        raise ValueError("LOAN_DW_TARGET must be DEMO, TEST, RESTORE, or E2E")
    container, dsn = TARGETS[target]
    if os.environ.get("ORACLE_CONTAINER", container) != container:
        raise ValueError("ORACLE_CONTAINER does not match the database target")
    if os.environ.get("ORACLE_DSN", dsn) != dsn:
        raise ValueError("ORACLE_DSN does not match the database target")
    return target, container, dsn


def require_test(connection):
    """Read the controlled marker on the same connection; refuse if the table is missing, empty, has several rows, or is not TEST."""
    with connection.cursor() as cursor:
        cursor.execute("select environment_name from loan_dw.database_environment")
        row = cursor.fetchone()
        if row != ("TEST",):
            raise RuntimeError("Write tests are allowed only on the TEST database; nothing was written")
        # The marker table has a single-row constraint; a same-named table without it is still not trusted.
        if hasattr(cursor, "fetchall") and cursor.fetchall():
            raise RuntimeError("The TEST environment marker must have exactly one row")


if __name__ == "__main__":
    import sys

    target, container, dsn = settings()
    print({"target": target, "container": container, "dsn": dsn}[sys.argv[1]])
