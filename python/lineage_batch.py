"""Verify the raw archives, the text actually loaded, and ODS, and keep a separate batch ID for every load.

Usage: python python/lineage_batch.py backfill
      python python/lineage_batch.py begin RELEASE RUN_ID
      python python/lineage_batch.py finish RELEASE BATCH_ID
      python python/lineage_batch.py fail BATCH_ID
backfill verifies each existing release in turn, leaving the old run_id empty; a normal load calls begin before loading ODS,
finish when done, and fail on failure. Failed records are kept but cannot be referenced by ADS calculations.
"""

import hashlib
import os
import re
import sys
import zipfile
from pathlib import Path

from db import connect
from raw_manifest import read_manifest, sha256_of

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT.parent / "data/raw"
EXTRACTED = ROOT.parent / "data/extracted"
# Raw archive manifest; for a sample you downloaded yourself, point LOAN_RAW_MANIFEST at the manifest you built
MANIFEST = Path(os.environ.get("LOAN_RAW_MANIFEST", ROOT / "docs/raw_manifest.csv"))
RELEASES = ("R45", "R46", "R47")


def files_for(cur, release):
    """Take the file list from the data of this release currently in ODS, instead of hard-coding a file count for one computer's directory layout."""
    cur.execute(
        "select 'ods_orig', source_file from ods_orig where release_id = :r "
        "group by source_file union all "
        "select 'ods_perf', source_file from ods_perf where release_id = :r "
        "group by source_file union all "
        "select 'ods_orig_pre202607', source_file from ods_orig_pre202607 "
        "where release_id = :r group by source_file union all "
        "select 'ods_perf_pre202607', source_file from ods_perf_pre202607 "
        "where release_id = :r group by source_file order by 1, 2",
        r=release,
    )
    found = []
    for table, name in cur.fetchall():
        year = re.search(r"_(\d{4})\.txt$", name)
        if not year:
            raise ValueError(f"No year in the source file name: {name}")
        found.append((table, EXTRACTED / release / f"sample_{year.group(1)}" / name))
    if not found:
        raise ValueError(f"{release} has no data in ODS")
    return found


def zip_for(release, source_file, entries):
    """Find the one ZIP of this release in the manifest that contains this file; fail if there is none or more than one."""
    hits = []
    for rel in sorted(entries):
        if rel.startswith(f"{release}/") and rel.endswith(".zip"):
            with zipfile.ZipFile(RAW / rel) as archive:
                if source_file in archive.namelist():
                    hits.append(rel)
    if len(hits) != 1:
        raise ValueError(
            f"Manifest ZIPs containing {source_file}: expected 1, found {len(hits)}"
        )
    return hits[0], source_file, entries[hits[0]]


def stream_sha(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def text_fingerprint(path):
    rows = 0
    total = 0
    with open(path, encoding="utf-8", newline="") as source:
        for line in source:
            fields = line.rstrip("\r\n").split("|")
            canonical = "".join(
                "~" if not value else f"{len(value)}:{value}" for value in fields
            )
            total += int(hashlib.sha256(canonical.encode()).hexdigest()[:15], 16)
            rows += 1
    return rows, f"{rows}/{total}"


def inspect_file(cur, release, table, path, entries):
    name = path.name
    rel, member, expected = zip_for(release, name, entries)
    zip_path = RAW / rel
    if not path.is_file() or not zip_path.is_file():
        raise FileNotFoundError(f"Missing source file: {path} or {zip_path}")
    if zip_path.stat().st_size != int(expected["size_bytes"]):
        raise ValueError(f"Original ZIP size mismatch: {rel}")
    actual_zip_sha = sha256_of(zip_path)
    if actual_zip_sha != expected["sha256"]:
        raise ValueError(f"Original ZIP SHA-256 mismatch: {rel}")
    with zipfile.ZipFile(zip_path) as archive, archive.open(member) as stream:
        member_sha = stream_sha(stream)
    source_sha = sha256_of(path)
    if source_sha != member_sha:
        raise ValueError(f"Extracted text differs from the ZIP member: {name}")
    source_rows, expected_ods_hash = text_fingerprint(path)
    cur.execute(
        f"select count(*) from {table} where release_id = :r and source_file = :f",
        r=release,
        f=name,
    )
    ods_rows = cur.fetchone()[0]
    cur.execute(
        "select ods_file_hash(:t, :r, :f) from dual", t=table, r=release, f=name
    )
    ods_hash = cur.fetchone()[0]
    if source_rows != ods_rows or expected_ods_hash != ods_hash:
        raise ValueError(
            f"{release} {name} source file {source_rows}/{expected_ods_hash}, "
            f"ODS {ods_rows}/{ods_hash} differ"
        )
    label = "ZIP/member/source text/ODS agree"
    print(f"{release} {table} {name}: {source_rows} rows, {label}", flush=True)
    return (
        table,
        name,
        rel,
        actual_zip_sha,
        int(expected["size_bytes"]),
        member,
        member_sha,
        path.stat().st_size,
        source_sha,
        source_rows,
        ods_rows,
        ods_hash,
    )


def begin(release, run_id):
    if release not in RELEASES:
        raise ValueError(release)
    source = "FRE"
    with connect() as conn, conn.cursor() as cur:
        batch_id = cur.var(int)
        cur.execute(
            "insert into etl_source_batch "
            "(data_source, release_id, run_id, status, format_version) "
            "values (:s, :r, :run, 'STARTED', :fmt) returning source_batch_id into :id",
            s=source,
            r=release,
            run=run_id,
            fmt="FRE_OLD" if release in ("R45", "R46") else "FRE_NEW",
            id=batch_id,
        )
        conn.commit()
        return batch_id.getvalue()[0]


def fail(batch_id, reason="Load or verification failed"):
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "update etl_source_batch set status = 'FAILED', error_message = :reason "
            "where source_batch_id = :id and status = 'STARTED'",
            id=batch_id,
            reason=reason[:1000],
        )
        conn.commit()


def finish(release, batch_id, legacy=False):
    entries = read_manifest(MANIFEST)
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "select release_id, status from etl_source_batch where source_batch_id = :id",
            id=batch_id,
        )
        if cur.fetchone() != (release, "STARTED"):
            raise ValueError("Batch missing, release mismatch, or already closed")
        records = [
            inspect_file(cur, release, table, path, entries)
            for table, path in files_for(cur, release)
        ]
        digest = hashlib.sha256()
        for row in records:
            digest.update("|".join(map(str, row)).encode())
            digest.update(b"\n")
        for row in records:
            cur.execute(
                "insert into etl_source_batch_file "
                "(source_batch_id, source_table, source_file, zip_path, zip_sha256, "
                "zip_bytes, member_name, member_sha256, source_bytes, source_sha256, "
                "source_rows, ods_rows, ods_hash) "
                "values (:id, :t, :f, :z, :zh, :zb, :m, :mh, :sb, :sh, :sr, :orows, :oh)",
                id=batch_id,
                t=row[0],
                f=row[1],
                z=row[2],
                zh=row[3],
                zb=row[4],
                m=row[5],
                mh=row[6],
                sb=row[7],
                sh=row[8],
                sr=row[9],
                orows=row[10],
                oh=row[11],
            )
        cur.execute(
            "update etl_source_batch set status = :status, verified_at = systimestamp, "
            "row_count = :row_total, batch_digest = :digest where source_batch_id = :id",
            status="LEGACY_VERIFIED" if legacy else "SUCCESS",
            row_total=sum(row[10] for row in records),
            digest=digest.hexdigest(),
            id=batch_id,
        )
        conn.commit()
        print(
            f"{release} batch {batch_id}: {len(records)} files, {sum(r[10] for r in records)} rows, verified"
        )


def main():
    args = sys.argv[1:]
    if args == ["backfill"]:
        for release in RELEASES:
            batch_id = begin(release, None)
            try:
                finish(release, batch_id, legacy=True)
            except Exception:
                fail(batch_id)
                raise
    elif len(args) == 3 and args[0] == "begin":
        print(begin(args[1], int(args[2])))
    elif len(args) == 3 and args[0] == "finish":
        finish(args[1], int(args[2]))
    elif len(args) >= 2 and args[0] == "fail":
        fail(int(args[1]), " ".join(args[2:]) or "Load or verification failed")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
