"""Raw archive manifest: record the size and SHA-256 checksum of every file in data/raw; verify before loading and stop on any mismatch.

Usage:
  python python/raw_manifest.py build  <raw data folder> <manifest file>
  python python/raw_manifest.py verify <raw data folder> <manifest file>
Example: python python/raw_manifest.py verify ../data/raw docs/raw_manifest.csv
build: add checksums for files not yet in the manifest; files already listed are only checked, never rewritten
       (raw files are never modified, project convention; a changed checksum means the file is damaged or was
       replaced, which must raise an error instead of being overwritten silently).
verify: recompute the checksum of every listed file; exit with failure if a file is missing or its size or checksum differs;
        files present in the folder but not in the manifest only produce a notice (run build for new downloads first).
file_time in the manifest is the file modification time (local time with time zone), used as an approximation of the
download time (the files are never modified after download).
Requires: Python standard library only. Called by: run manually; verify before loading (see Setup in README).
"""

import csv  # read and write the manifest
import datetime  # turn modification times into readable dates
import hashlib  # compute SHA-256
import os  # walk folders, read file information
import sys  # read command-line arguments, set the exit status

FIELDS = ["path", "folder", "size_bytes", "sha256", "file_time"]  # manifest columns
# read 8 MB at a time so large files do not fill memory (project convention)
CHUNK = 8 * 1024 * 1024


def checked_relative_path(rel):
    """A manifest path may only point to a plain relative location inside the raw data folder."""
    normalized = os.path.normpath(rel)
    if (
        not rel
        or os.path.isabs(rel)
        or normalized != rel
        or normalized == os.pardir
        or normalized.startswith(os.pardir + os.sep)
    ):
        raise ValueError(f"Unsafe path in manifest: {rel!r}")
    return normalized


def full_path(raw_dir, rel):
    """Place a manifest relative path safely under raw_dir and reject symbolic-link escapes."""
    rel = checked_relative_path(rel)
    root = os.path.realpath(raw_dir)
    full = os.path.realpath(os.path.join(root, rel))
    if os.path.commonpath((root, full)) != root:
        raise ValueError(f"Unsafe path in manifest: {rel!r}")
    return full


def sha256_of(path):  # compute a file's SHA-256 and return it as a hex string
    h = hashlib.sha256()  # new checksum calculator
    with open(path, "rb") as f:  # read as binary
        # read block by block to the end of the file
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)  # add this block to the calculation
    return h.hexdigest()  # return the result


# list all files under the raw data folder (relative paths), skipping hidden files
def list_files(raw_dir):
    found = []  # result
    for root, dirs, files in os.walk(raw_dir):  # walk level by level
        # skip hidden folders
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for name in sorted(files):  # sort by name for a stable result
            if not name.startswith("."):  # skip system files such as .DS_Store
                full = os.path.join(root, name)  # full path
                # path relative to the raw data folder
                found.append(os.path.relpath(full, raw_dir))
    return found


def describe(raw_dir, rel):  # compute one file's manifest row
    full = full_path(raw_dir, rel)  # full path
    stat = os.stat(full)  # file size and modification time
    # modification time
    mtime = datetime.datetime.fromtimestamp(stat.st_mtime, tz=datetime.UTC)
    return {
        "path": rel,  # relative path, e.g. R47/R47_sample_2010.zip
        # first-level folder, i.e. the release, e.g. R47
        "folder": rel.split(os.sep)[0],
        "size_bytes": str(stat.st_size),  # size in bytes
        "sha256": sha256_of(full),  # checksum
        # local time and time zone
        "file_time": mtime.astimezone().strftime("%Y-%m-%d %H:%M %z"),
    }


# read the manifest and return {relative path: row}; empty if it does not exist
def read_manifest(path):
    if not os.path.exists(path):  # there is no manifest yet on the first build
        return {}
    entries = {}
    with open(path, encoding="utf-8", newline="") as f:  # open the manifest
        reader = csv.DictReader(f)
        if reader.fieldnames != FIELDS:
            raise ValueError(
                f"Wrong manifest header: expected {FIELDS}, got {reader.fieldnames}"
            )
        for row in reader:
            rel = checked_relative_path(row["path"])
            if rel in entries:
                raise ValueError(f"Duplicate path in manifest: {rel}")
            entries[rel] = row
    return entries


# add new files to the manifest; existing ones are only checked
def build(raw_dir, manifest_path):
    entries = read_manifest(manifest_path)  # the existing manifest
    # check existing entries first; stop if any differ
    problems = verify_entries(raw_dir, entries)
    if problems:  # an existing file does not match
        # start of the error
        msg = "Files already in the manifest do not match; the manifest was not rewritten:\n"
        raise SystemExit(msg + "\n".join(problems))
    added = 0  # number of files added
    for rel in list_files(raw_dir):  # every file in the folder
        if rel not in entries:  # not in the manifest yet
            entries[rel] = describe(raw_dir, rel)  # compute its row
            added += 1
            print(f"Added: {rel}  {entries[rel]['sha256']}")
    # write the manifest back
    with open(manifest_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)  # write with fixed columns
        writer.writeheader()  # header
        for rel in sorted(entries):  # sorted by path so git diffs stay readable
            writer.writerow(entries[rel])
    print(
        f"Manifest has {len(entries)} files, {added} added this time: {manifest_path}"
    )


# check the listed files and return a list of problems (empty = all match)
def verify_entries(raw_dir, entries):
    problems = []  # problems
    for rel, row in sorted(entries.items()):  # every file in the manifest
        try:
            full = full_path(raw_dir, rel)  # full path
        except ValueError as exc:
            problems.append(str(exc))
            continue
        if not os.path.exists(full):  # the file is gone
            problems.append(f"Missing file: {rel}")
            continue
        # size differs; no need to compute the checksum
        if str(os.path.getsize(full)) != row["size_bytes"]:
            problems.append(f"Size mismatch: {rel}")
            continue
        if sha256_of(full) != row["sha256"]:  # checksum differs
            problems.append(f"Checksum mismatch: {rel}")
    return problems


def verify(raw_dir, manifest_path):  # verify; exit with failure if anything is wrong
    entries = read_manifest(manifest_path)  # read the manifest
    if not entries:  # no manifest, or an empty one
        raise SystemExit(f"Manifest missing or empty: {manifest_path}")
    problems = verify_entries(raw_dir, entries)  # check each file
    for rel in list_files(raw_dir):  # files in the folder but not in the manifest
        if rel not in entries:
            print(
                f"Notice: {rel} is not in the manifest (run build for newly downloaded files first)"
            )
    if problems:  # any mismatch at all
        raise SystemExit("Verification failed; do not load:\n" + "\n".join(problems))
    print(f"All {len(entries)} files in the manifest match")


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("build", "verify"):  # wrong arguments
        raise SystemExit(__doc__)  # print usage
    mode, raw_dir, manifest_path = sys.argv[1:]  # mode, raw data folder, manifest file
    if mode == "build":
        build(raw_dir, manifest_path)
    else:
        verify(raw_dir, manifest_path)
