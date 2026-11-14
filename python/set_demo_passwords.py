"""Generate random login passwords for the review system's demo users.

Usage: python python/set_demo_passwords.py <file to write the plain-text passwords to>
For example: python python/set_demo_passwords.py app/demo-users.local.txt
The database stores only BCrypt hashes; the plain text goes only to this local file (excluded by .gitignore, never in git),
which you open yourself. Every run sets new passwords. Hashes are made with htpasswd ($2y$ format, accepted by Spring Security).
Requires: python/db.py; app_user has password_hash and the lockout columns.
Changing passwords also clears the lockout, so this also rescues a demo account locked after repeated wrong passwords.
Called by: scripts/11_set_demo_passwords.sh.
"""

import secrets  # random passwords (cryptographically secure random numbers)
import subprocess  # call htpasswd
import sys  # read command-line arguments
import tempfile  # write a temporary file safely in the target directory, then replace atomically
from pathlib import Path  # check the output path and set file permissions

from db import connect  # database connection

DEMO_USERS = ["analyst_demo", "manager_demo"]  # demo users in oltp_seed.sql


def bcrypt_hash(password):
    """Compute a BCrypt hash (cost 10) with htpasswd; the password goes through stdin, never on the command line."""
    out = subprocess.run(
        ["htpasswd", "-niB", "-C", "10", "user"],
        input=password,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return out.split(":", 1)[1]  # output is "user:$2y$10$..."


def checked_password_path(out_path):
    """Confirm the plain-text output path is usable before changing the database."""
    path = Path(out_path)
    if path.exists() and not path.is_file():
        raise ValueError(f"Password output path is not a regular file: {path}")
    if not path.parent.is_dir():
        raise ValueError(f"Password output directory does not exist: {path.parent}")
    return path


def stage_password_file(path, lines):
    """Write a temporary file with permission 0600 in the target directory first."""
    fd, temp_path = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent, text=True
    )
    try:
        with open(fd, "w", encoding="utf-8", closefd=True) as f:
            f.write("\n".join(lines) + "\n")
        Path(temp_path).chmod(0o600)
    except BaseException:
        Path(temp_path).unlink(missing_ok=True)
        raise
    return Path(temp_path)


def main(out_path):
    path = checked_password_path(out_path)
    lines = [
        "# Demo user login passwords (local file, not in git; rerun set_demo_passwords.py for new passwords)"
    ]
    credentials = []
    for username in DEMO_USERS:
        password = secrets.token_urlsafe(12)  # random 16-character password
        credentials.append((username, bcrypt_hash(password)))
        lines.append(f"{username}  {password}")

    # File system errors must surface before the database commit, so passwords are never changed without the plain text being written.
    staged = stage_password_file(path, lines)
    try:
        with connect() as conn, conn.cursor() as cur:
            for username, password_hash in credentials:
                cur.execute(
                    "update app_user set password_hash = :h, failed_login_count = 0, locked_until = null"
                    " where username = :u",
                    h=password_hash,
                    u=username,
                )
                if cur.rowcount != 1:  # user does not exist
                    conn.rollback()
                    raise SystemExit(f"User {username} not found (run oltp_seed.sql first)")
            conn.commit()
    except BaseException:
        staged.unlink(missing_ok=True)
        raise
    try:
        staged.replace(path)
    except OSError as exc:
        # After the database commit the only copy of the new passwords must not be deleted; report the recovery path without printing passwords.
        raise RuntimeError(
            f"Database passwords committed, but replacing the plain-text file failed; the new passwords are in {staged} (permission 0600)"
        ) from exc
    print(f"Set new passwords for {len(DEMO_USERS)} demo users; plain text in {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
