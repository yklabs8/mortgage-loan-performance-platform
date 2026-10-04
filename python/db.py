"""Connect to the project's Oracle database (FREEPDB1).

Password source: only a private file outside the repository. Stop if an account has no saved password.
Requires: python-oracledb. Called by: scripts in python/ that need the database.
"""

import os  # read environment variables

import oracledb  # official Oracle Python driver

from password_store import lookup


# get the database password; it stays in memory and is never printed
def password(user):
    return lookup(user)


def connect():  # return a database connection
    user = os.environ.get("ORACLE_USER", "loan_dw")  # user name, default loan_dw
    dsn = os.environ.get("ORACLE_DSN", "localhost:1521/FREEPDB1")  # host:port/service
    return oracledb.connect(user=user, password=password(user), dsn=dsn)
