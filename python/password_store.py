"""Read a database account's private file without logging the password."""

import getpass
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path


def file_path():
    """Keep the default password file outside the repository; tests may override it."""
    return Path(
        os.environ.get(
            "LOAN_DW_PASSWORD_FILE",
            Path.home() / ".config" / "loan-dw" / "passwords.json",
        )
    ).expanduser()


def read_entries(path):
    """Accept only a regular JSON file owned and readable by the current user."""
    try:
        info = path.lstat()
    except FileNotFoundError:
        return {}
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError("Password file must be a regular file")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise RuntimeError("Password file permission must be owner-only (chmod 600)")
    try:
        with path.open(encoding="utf-8") as stream:
            entries = json.load(stream)
    except (OSError, ValueError) as exc:
        raise RuntimeError("Cannot read password file as JSON") from exc
    if not isinstance(entries, dict):
        raise TypeError("Password file must contain a JSON object")
    return entries


def password_from_file(user):
    entries = read_entries(file_path())
    value = entries.get(user.lower())
    if value == "":
        return None
    if value is not None and not isinstance(value, str):
        raise TypeError("Password file has an invalid entry")
    if value is not None and any(ch in value for ch in "\r\n\x00"):
        raise RuntimeError("Password file has an invalid entry")
    return value


def save_password(user, password):
    """Atomically save to the private file without printing the password."""
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", user):
        raise ValueError("Invalid database user name")
    if not password or any(ch in password for ch in "\r\n\x00"):
        raise ValueError("Invalid password")
    path = file_path()
    folder = path.parent
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    folder_info = folder.lstat()
    if (
        not stat.S_ISDIR(folder_info.st_mode)
        or folder_info.st_uid != os.getuid()
        or stat.S_IMODE(folder_info.st_mode) & 0o077
    ):
        raise RuntimeError(
            "Password directory permission must be owner-only (chmod 700)"
        )
    entries = read_entries(path)
    entries[user.lower()] = password
    handle, temp_name = tempfile.mkstemp(prefix=".passwords-", dir=folder)
    try:
        os.fchmod(handle, 0o600)
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(entries, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def lookup(user):
    """Read only the private file and report a missing account entry."""
    password = password_from_file(user)
    if not password:
        raise RuntimeError(
            f"No saved password for {user}; run password_store.py set {user}"
        )
    return password


if __name__ == "__main__":
    if (
        (len(sys.argv) == 2 and sys.argv[1] == "set")
        or (len(sys.argv) == 3 and sys.argv[1] != "set")
        or len(sys.argv) not in (2, 3)
    ):
        raise SystemExit("Usage: password_store.py USER | set USER")
    try:
        if sys.argv[1] == "set":
            first = getpass.getpass(f"Existing database password for {sys.argv[2]}: ")
            second = getpass.getpass("Enter it again: ")
            if first != second:
                raise ValueError("Passwords do not match")
            save_password(sys.argv[2], first)
            print(f"Saved password for {sys.argv[2]}")
            raise SystemExit(0)
        result = lookup(sys.argv[1])
    except (RuntimeError, TypeError, ValueError) as exc:
        raise SystemExit(str(exc)) from exc
    sys.stdout.write(result)
