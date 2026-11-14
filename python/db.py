"""Connect to the platform's Oracle database (FREEPDB1).

Password source: only a private file outside the repository. Stop if an account has no saved password.
Requires: python-oracledb. Called by: scripts in python/ that need the database.
"""

import os  # read environment variables

import oracledb  # official Oracle Python driver

from database_target import require_test, settings
from password_store import lookup


def password(user):  # get the database password; it stays in memory and is never printed
    return lookup(user)


def connect():  # return a database connection
    user = os.environ.get("ORACLE_USER", "loan_dw")  # user name, default loan_dw
    dsn = settings()[2]
    connection = oracledb.connect(user=user, password=password(user), dsn=dsn)
    if os.environ.get("LOAN_DW_REQUIRE_TEST") == "1":
        try:
            require_test(connection)
        except Exception:
            connection.close()
            raise
    return connection


def connect_test_database():
    """Separate entry for write tests: even outside the full check run, verify the in-database marker first."""
    connection = connect()
    try:
        require_test(connection)
    except Exception:
        connection.close()
        raise
    return connection
