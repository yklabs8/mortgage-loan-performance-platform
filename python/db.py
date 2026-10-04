"""Connect to the project's Oracle database (FREEPDB1).

Password source, in order: environment variable ORACLE_PASSWORD (works on any system); if it is not set
and the macOS security command exists, the Keychain (service loan-dw-oracle); otherwise a prompt in the terminal.
Requires: python-oracledb. Called by: scripts in python/ that need the database.
"""

import getpass  # prompt for the password in the terminal without echo
import os  # read environment variables
import shutil  # check whether the security command exists
import subprocess  # call the macOS security command to read the Keychain

import oracledb  # official Oracle Python driver


# get the database password; it stays in memory and is never printed
def password(user):
    pw = os.environ.get("ORACLE_PASSWORD")  # 1. environment variable
    if pw:
        return pw
    if shutil.which("security"):  # 2. macOS Keychain
        # Keychain command: -a account, -s service, -w print only the password
        cmd = [
            "security",
            "find-generic-password",
            "-a",
            user,
            "-s",
            "loan-dw-oracle",
            "-w",
        ]
        # read the Keychain
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return out.stdout.rstrip("\n")
    # 3. typed in the terminal
    return getpass.getpass(f"Database password for {user}: ")


def connect():  # return a database connection
    user = os.environ.get("ORACLE_USER", "loan_dw")  # user name, default loan_dw
    dsn = os.environ.get("ORACLE_DSN", "localhost:1521/FREEPDB1")  # host:port/service
    return oracledb.connect(user=user, password=password(user), dsn=dsn)
