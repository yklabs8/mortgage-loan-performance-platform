"""Validate a candidate delivery package and merge it as loan_oltp in a single transaction; called by a scheduler or the command line.

Usage: .venv/bin/python python/candidate_import.py <delivery dir>
Requires: source/oltp/candidate_delivery.sql. Reads only the private password file and never uses the caller's account.
PREPARING is registered and committed separately; business rows, VALIDATED, and PUBLISHED share one transaction, and a failure leaves only FAILED.
"""

import fcntl
import hashlib
import json
import re
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import oracledb

from db import password
from export_candidate_rule import select_rule
from failure_codes import SpaceGuardError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "spark"))
from candidate_contract import (
    CANDIDATE_COLUMNS,
    DATE_COLUMNS,
    KEY,
    NUMERIC_COLUMNS,
    PERFORMANCE,
    validate_candidate_package,
)
from delivery_contract import read_file

MIB = 1048576
BUSINESS_TABLES = [
    "review_candidate",
    "review_evidence",
    "review_evidence_month",
    "review_candidate_stage",
    "review_evidence_stage",
    "review_evidence_month_stage",
]


def connection():
    """Fixed review database account; unaffected by ORACLE_USER and needs no cross-schema privileges."""
    import os

    from database_target import require_test, settings

    conn = oracledb.connect(
        user="loan_oltp", password=password("loan_oltp"), dsn=settings()[2]
    )
    if os.environ.get("LOAN_DW_REQUIRE_TEST") == "1":
        try:
            require_test(conn)
        except Exception:
            conn.close()
            raise
    return conn


def content_digest(row, monthly):
    """Independently recompute Spark's fixed-column-order JSON, keeping NULL, leading zeros, and decimal(22,8)."""
    integers = {
        "rule_version_id",
        "version_no",
        "min_delinquency_status",
        "origination_year",
    }

    def scalar(key, value):
        if value is None or (value == "" and key != "missing_months"):
            return "null"
        if key in NUMERIC_COLUMNS:
            number = Decimal(str(value))
            return (
                str(int(number))
                if key in integers
                else str(number.quantize(Decimal("0.00000001")))
            )
        if key == "previous_month_missing":
            return str(value).lower()
        return json.dumps(str(value), ensure_ascii=False, separators=(",", ":"))

    def obj(values, keys):
        return (
            "{"
            + ",".join(json.dumps(k) + ":" + scalar(k, values[k]) for k in keys)
            + "}"
        )

    cols = [c for c in CANDIDATE_COLUMNS["review_evidence"] if c != "content_sha256"]
    keys = ["monthly_reporting_period"] + PERFORMANCE
    payload = (
        obj(row, cols)[:-1]
        + ',"months":['
        + ",".join(
            obj(m, keys)
            for m in sorted(monthly, key=lambda m: m["monthly_reporting_period"])
        )
        + "]}"
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def key(row):
    return tuple(row[c] for c in KEY)


def load_rows(folder, manifest):
    """Validate business keys, digests, rules, and months; a valid file digest must not hide wrong business content."""
    rows = {}
    for item in manifest["files"]:
        t = item["table"]
        if t in CANDIDATE_COLUMNS:
            rows[t] = [
                dict(zip(item["columns"], r, strict=True))
                for r in read_file(folder / item["path"], item["columns"])
            ]
    indexed = {}
    for t in ["review_candidate", "review_evidence"]:
        indexed[t] = {}
        for row in rows[t]:
            if key(row) in indexed[t]:
                raise ValueError("Duplicate candidate business key")
            indexed[t][key(row)] = row
    candidates, evidence = indexed["review_candidate"], indexed["review_evidence"]
    if candidates.keys() != evidence.keys():
        raise ValueError("Candidate and evidence business keys differ")
    months = {k: {} for k in candidates}
    report = date.fromisoformat(manifest["reporting_month"])
    lower = report.replace(year=report.year - 1)
    for row in rows["review_evidence_month"]:
        k = key(row)
        month = date.fromisoformat(row["monthly_reporting_period"])
        if k not in months or month.day != 1 or not lower <= month <= report:
            raise ValueError("Orphan or out-of-range monthly evidence")
        if month.isoformat() in months[k]:
            raise ValueError("Duplicate monthly evidence")
        months[k][month.isoformat()] = row
    for k, row in evidence.items():
        candidate = candidates[k]
        if (
            row["rule_version_id"] != str(manifest["rule"]["rule_version_id"])
            or row["reporting_month"] != manifest["reporting_month"]
            or row["data_source"] != "FRE"
            or not re.fullmatch(r"[A-Za-z0-9]{12}", row["loan_identifier"])
            or row["source_release_id"] != manifest["release"]
            or any(
                row[c] != str(manifest["rule"][c])
                for c in ["rule_code", "version_no", "min_delinquency_status"]
            )
            or row["origination_year"] not in {str(y) for y in manifest["source_years"]}
            or candidate["source_release_id"] != row["source_release_id"]
            or candidate["delinquency_status"] != row["current_loan_delinquency_status"]
        ):
            raise ValueError("Candidate scope or row rule mismatch")
        available = months[k]
        if report.isoformat() not in available:
            raise ValueError("Evidence is missing the reporting month")
        if any(row[c] != available[report.isoformat()][c] for c in PERFORMANCE):
            raise ValueError("Reporting-month evidence fields differ")
        expected_missing = []
        for offset in range(13):
            n = report.year * 12 + report.month - 1 - offset
            month = date(n // 12, n % 12 + 1, 1).isoformat()
            if month not in available:
                expected_missing.append(month)
        previous_n = report.year * 12 + report.month - 2
        previous = date(previous_n // 12, previous_n % 12 + 1, 1).isoformat()
        if (
            row["missing_months"] != "|".join(sorted(expected_missing))
            or row["previous_month_missing"] != str(previous not in available).lower()
            or row["previous_delinquency_status"]
            != available.get(previous, {}).get("current_loan_delinquency_status", "")
        ):
            raise ValueError("Missing months or previous-month flag mismatch")

        def level(value):
            return (
                99
                if value == "RA"
                else int(value)
                if re.fullmatch(r"[0-9]+", value or "")
                else None
            )

        current = level(row["current_loan_delinquency_status"])
        prev = level(row["previous_delinquency_status"]) or 0
        threshold = manifest["rule"]["min_delinquency_status"]
        if current is None or current < threshold or prev >= threshold:
            raise ValueError("Candidate does not satisfy the rule")
        if content_digest(row, list(available.values())) != row["content_sha256"]:
            raise ValueError("Evidence content digest mismatch")
    return rows


def usage(cur):
    names = BUSINESS_TABLES + [
        "review_candidate_delivery",
        "review_candidate_import_lock",
    ]
    binds = {"n" + str(i): t.upper() for i, t in enumerate(names)}
    placeholders = ",".join(":" + n for n in binds)
    cur.execute(
        f"""select coalesce(sum(bytes),0) from user_segments where segment_name in
        (select table_name from user_tables where table_name in ({placeholders})
         union select index_name from user_indexes where table_name in ({placeholders})
         union select segment_name from user_lobs where table_name in ({placeholders})
         union select index_name from user_lobs where table_name in ({placeholders}))""",
        binds,
    )
    return cur.fetchone()[0]


def guard(cur, reserve=0):
    cur.execute("select sum(bytes) from user_free_space where tablespace_name='USERS'")
    free = cur.fetchone()[0]
    used = usage(cur)
    # All candidate objects (including registration LOBs) are conservatively counted against 160 MiB; the shared 20 MiB record budget is untouched.
    if used + reserve > 160 * MIB or free is None or free - reserve < 500 * MIB:
        raise SpaceGuardError("Not enough room: candidate 160 MiB budget or at least 500 MiB free in USERS")
    return {"candidate_bytes": used, "users_free_bytes": free}


def convert(column, value):
    if value == "":
        return None
    if column in DATE_COLUMNS:
        return datetime.fromisoformat(value)
    if column in NUMERIC_COLUMNS:
        number = Decimal(value)
        if not number.is_finite():
            raise ValueError("Non-finite number")
        return number
    return value


def stage(cur, folder, manifest, rows):
    for table, columns in CANDIDATE_COLUMNS.items():
        values = [tuple(convert(c, row[c]) for c in columns) for row in rows[table]]
        if values:
            cur.executemany(
                f"insert into {table}_stage ({','.join(columns)}) values ({','.join(':' + str(i + 1) for i in range(len(columns)))})",
                values,
            )
        cur.execute(f"select count(*) from {table}_stage")
        expected = next(i["rows"] for i in manifest["files"] if i["table"] == table)
        if cur.fetchone()[0] != expected:
            raise ValueError("Stage table row count mismatch")

        # Read back from the database independently and compare every value by column type, not just row counts.
        def decimal_handler(cursor, metadata):
            if metadata.type_code == oracledb.DB_TYPE_NUMBER:
                return cursor.var(
                    oracledb.DB_TYPE_VARCHAR,
                    arraysize=cursor.arraysize,
                    outconverter=Decimal,
                )

        cur.outputtypehandler = decimal_handler
        cur.execute(f"select {','.join(columns)} from {table}_stage")
        actual = set(cur.fetchall())
        cur.outputtypehandler = None
        if actual != set(values):
            raise ValueError("Stage table cell-by-cell check mismatch")


def merge(cur, delivery, after_merge):
    match = " and ".join("c." + c + "=s." + c for c in KEY)
    cur.execute(f"""merge into review_candidate c using review_candidate_stage s on ({match})
        when matched then update set c.candidate_source='SPARK'
        when not matched then insert ({",".join(CANDIDATE_COLUMNS["review_candidate"])},candidate_source)
        values ({",".join("s." + c for c in CANDIDATE_COLUMNS["review_candidate"])},'SPARK')""")
    after_merge("review_candidate")
    cols = CANDIDATE_COLUMNS["review_evidence"]
    cur.execute(
        f"""insert into review_evidence (candidate_id,delivery_id,{",".join(cols)})
        select c.candidate_id,:d,{",".join("s." + c for c in cols)}
        from review_evidence_stage s join review_candidate c on {match}
        where not exists (select 1 from review_evidence e where e.candidate_id=c.candidate_id and e.content_sha256=s.content_sha256)""",
        d=delivery,
    )
    after_merge("review_evidence")
    # Only months of new evidence are added; a delivery with identical content reuses existing evidence and months.
    monthcols = [c for c in CANDIDATE_COLUMNS["review_evidence_month"] if c not in KEY]
    cur.execute(f"""insert into review_evidence_month (evidence_id,{",".join(monthcols)})
        select e.evidence_id,{",".join("s." + c for c in monthcols)}
        from review_evidence_month_stage s join review_candidate c on {match}
        join review_evidence_stage v on {" and ".join("v." + c + "=s." + c for c in KEY)}
        join review_evidence e on e.candidate_id=c.candidate_id and e.content_sha256=v.content_sha256
        where not exists (select 1 from review_evidence_month m where m.evidence_id=e.evidence_id and m.monthly_reporting_period=s.monthly_reporting_period)""")
    after_merge("review_evidence_month")
    cur.execute(f"""merge into review_candidate c using
        (select c.candidate_id,e.evidence_id from review_evidence_stage s
         join review_candidate c on {match}
         join review_evidence e on e.candidate_id=c.candidate_id and e.content_sha256=s.content_sha256) v
        on (c.candidate_id=v.candidate_id)
        when matched then update set c.latest_evidence_id=v.evidence_id""")


def publish(folder, after_merge=lambda _table: None):
    folder = Path(folder).resolve()
    text = (folder / "manifest.json").read_text()
    m = json.loads(text)
    delivery_hex = m.get("delivery_id", "")
    if not re.fullmatch(r"[0-9a-f]{32}", delivery_hex):
        raise ValueError("Invalid delivery_id")
    delivery = bytes.fromhex(delivery_hex)
    sha = hashlib.sha256(text.encode()).hexdigest()
    lockpath = Path(__file__).resolve().parents[1] / "data/locks/candidate_import.lock"
    lockpath.parent.mkdir(parents=True, exist_ok=True)
    with lockpath.open("a") as lock, connection() as conn, conn.cursor() as cur:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cur.execute(
            "select lock_id from review_candidate_import_lock where lock_id=1 for update wait 3"
        )
        cur.fetchone()
        cur.execute(
            "select status,manifest_sha256 from review_candidate_delivery where delivery_id=:d",
            d=delivery,
        )
        prior = cur.fetchone()
        if prior and prior[1] != sha:
            raise ValueError("Same delivery ID with different content")
        if prior and prior[0] == "PUBLISHED":
            validate_candidate_package(folder)
            return delivery_hex
        # Estimate all CSVs plus indexes and two in-flight copies first, so an oversized package is stopped before it is read into memory.
        reserve = sum(p.stat().st_size for p in folder.rglob("*.csv")) * 6 + 4 * MIB
        guard(cur, reserve)
        if prior:
            cur.execute(
                "update review_candidate_delivery set status='PREPARING',error_message=null where delivery_id=:d and status!='PUBLISHED'",
                d=delivery,
            )
        else:
            cur.execute(
                "insert into review_candidate_delivery (delivery_id,manifest_sha256,manifest_json,status) values (:d,:h,:j,'PREPARING')",
                d=delivery,
                h=sha,
                j=text,
            )
        conn.commit()
        try:
            # A database row lock also protects imports from different machines; stage tables are session-private temporary tables.
            cur.execute(
                "select lock_id from review_candidate_import_lock where lock_id=1 for update wait 3"
            )
            cur.fetchone()
            cur.execute(
                "select status,manifest_sha256 from review_candidate_delivery where delivery_id=:d for update",
                d=delivery,
            )
            status, recorded_sha = cur.fetchone()
            if recorded_sha != sha:
                raise ValueError("Same delivery ID with different content")
            if status == "PUBLISHED":
                return delivery_hex
            m = validate_candidate_package(folder)
            if (folder / "manifest.json").read_text() != text:
                raise ValueError("Manifest changed during validation")
            if select_rule(cur, m["reporting_month"]) != m["rule"]:
                raise ValueError("Manifest rule version or threshold differs from the database")
            guard(cur, reserve)
            rows = load_rows(folder, m)
            stage(cur, folder, m, rows)
            cur.execute(
                "update review_candidate_delivery set status='VALIDATED' where delivery_id=:d",
                d=delivery,
            )
            merge(cur, delivery, after_merge)
            guard(cur)
            cur.execute(
                "update review_candidate_delivery set status='PUBLISHED',published_at=systimestamp where delivery_id=:d",
                d=delivery,
            )
            conn.commit()
        except Exception as error:
            conn.rollback()
            message = str(error).encode()[:3900].decode("utf-8", errors="ignore")
            cur.execute(
                "update review_candidate_delivery set status='FAILED',error_message=:e where delivery_id=:d and status!='PUBLISHED'",
                d=delivery,
                e=message,
            )
            conn.commit()
            raise
    return delivery_hex


def boundary():
    """Row-by-row digests before and after a full check, covering existing candidates/cases and every object of this feature."""
    result = {}
    with connection() as conn, conn.cursor() as cur:
        cur.execute("set transaction read only")
        for table in BUSINESS_TABLES + [
            "risk_review_case",
            "review_candidate_delivery",
        ]:
            cur.execute(
                "select column_name from user_tab_columns where table_name=:t order by column_id",
                t=table.upper(),
            )
            cols = [r[0].lower() for r in cur.fetchall()]
            cur.execute(f"select {','.join(cols)} from {table}")
            hashes = []
            for row in cur:
                values = [v.read() if hasattr(v, "read") else v for v in row]
                hashes.append(
                    hashlib.sha256(
                        json.dumps(values, default=str, ensure_ascii=False).encode()
                    ).hexdigest()
                )
            result[table] = {
                "rows": len(hashes),
                "sha256": hashlib.sha256("".join(sorted(hashes)).encode()).hexdigest(),
            }
    return result


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] in {"--save-boundary", "--check-boundary"}:
        path = Path(sys.argv[2])
        actual = boundary()
        if sys.argv[1] == "--save-boundary":
            path.write_text(json.dumps(actual, indent=2) + "\n")
        elif actual != json.loads(path.read_text()):
            sys.exit("Candidate/evidence/registration/case content changed: the check left residue or rewrote existing data")
        else:
            print("Candidate/evidence/registration/case row digests agree: no test residue")
    elif len(sys.argv) == 2:
        print("Candidates published", publish(sys.argv[1]))
    else:
        sys.exit(__doc__)
