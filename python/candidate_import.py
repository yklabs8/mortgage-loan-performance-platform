"""Select review candidates in Oracle and publish them as loan_oltp in a single transaction; called by a scheduler or the command line.

Usage: .venv/bin/python python/candidate_import.py <release> <reporting month, first day: YYYY-MM-01>
Requires: source/oltp/candidate_delivery.sql and candidate_publish.sql. Reads only the private password file and never uses the caller's account.
Steps: the PL/SQL procedure candidate_publish.stage_month applies the review rule to the warehouse and fills this session's stage tables;
this program then checks every staged row independently (business keys, rule, months, digests) and merges them in the same transaction.
The delivery ID is derived from the manifest, so identical content is published once and a repeated run changes nothing.
PREPARING and FAILED are recorded on a second connection; business rows, VALIDATED, and PUBLISHED share one transaction.
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
from failure_codes import SpaceGuardError

MIB = 1048576
RULE_CODE = "DLQ60_ENTRY"
KEY = ["rule_version_id", "data_source", "loan_identifier", "reporting_month"]
ORIGIN = [
    "classic_fico",
    "original_upb",
    "original_loan_to_value_ltv",
    "original_interest_rate",
    "property_state",
    "origination_year",
    "first_payment_date",
]
PERFORMANCE = [
    "current_loan_delinquency_status",
    "current_actual_upb",
    "current_interest_rate",
    "zero_balance_code",
    "zero_balance_effective_date",
    "modification_flag",
]
# Column order of each stage table; the evidence digest uses this order (source/oltp/candidate_publish.sql)
CANDIDATE_COLUMNS = {
    "review_candidate": KEY + ["delinquency_status", "source_release_id"],
    "review_evidence": KEY
    + ["source_release_id", "rule_code", "version_no", "min_delinquency_status"]
    + ORIGIN
    + PERFORMANCE
    + [
        "previous_delinquency_status",
        "previous_month_missing",
        "missing_months",
        "content_sha256",
    ],
    "review_evidence_month": KEY + ["monthly_reporting_period"] + PERFORMANCE,
}
BUSINESS_TABLES = [
    "review_candidate",
    "review_evidence",
    "review_evidence_month",
    "review_candidate_stage",
    "review_evidence_stage",
    "review_evidence_month_stage",
]


def connection():
    """Fixed review database account; unaffected by ORACLE_USER."""
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


def first_of_month(reporting_month):
    month = date.fromisoformat(reporting_month)
    if month.day != 1 or month.isoformat() != reporting_month:
        raise ValueError(
            "The reporting month must be the first day of a month (YYYY-MM-01)"
        )
    return month


def select_rule(cur, reporting_month):
    """The rule version in effect for the month: effective date descending, then version descending."""
    month = first_of_month(reporting_month)
    cur.execute(
        """select v.rule_version_id, v.version_no, v.min_delinquency_status,
        v.effective_from from review_rule_version v
        join review_rule r on r.rule_id=v.rule_id
        where r.rule_code=:code and r.is_active='Y' and v.effective_from<=:month
        order by v.effective_from desc, v.version_no desc fetch first 1 row only""",
        code=RULE_CODE,
        month=month,
    )
    row = cur.fetchone()
    if row is None:
        raise ValueError(f"No effective {RULE_CODE} rule")
    if any(value != int(value) for value in row[:3]):
        raise ValueError("Rule version or threshold is not an integer")
    return {
        "rule_code": RULE_CODE,
        "rule_version_id": int(row[0]),
        "version_no": int(row[1]),
        "min_delinquency_status": int(row[2]),
        "effective_from": row[3].date().isoformat(),
    }


def canonical(value):
    """Digest text of one value, as in candidate_publish.seal: numbers with three decimals, dates as YYYY-MM-DD, NULL as empty."""
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d")
    if isinstance(value, (Decimal, int)):
        return format(Decimal(value).quantize(Decimal("0.001")), "f")
    return str(value)


def content_digest(row, monthly):
    """Recompute an evidence digest independently from the staged values."""
    columns = [c for c in CANDIDATE_COLUMNS["review_evidence"] if c != "content_sha256"]
    keys = ["monthly_reporting_period"] + PERFORMANCE
    text = (
        "|".join(canonical(row[c]) for c in columns)
        + "#"
        + ";".join(
            "|".join(canonical(m[k]) for k in keys)
            for m in sorted(monthly, key=lambda m: m["monthly_reporting_period"])
        )
    )
    return hashlib.sha256(text.encode()).hexdigest()


def delivery_digest(evidence):
    """Content digest of a delivery, as in candidate_publish.seal: evidence digests chained in business-key order."""
    chain = ""
    for row in sorted(
        evidence,
        key=lambda r: (
            r["data_source"],
            r["loan_identifier"],
            r["reporting_month"],
            r["rule_version_id"],
        ),
    ):
        chain += row["content_sha256"]
        if len(chain) > 3800:
            chain = hashlib.sha256(chain.encode()).hexdigest()
    return hashlib.sha256((chain + "#").encode()).hexdigest()


def read_stage(cur):
    def decimal_handler(cursor, metadata):
        if metadata.type_code == oracledb.DB_TYPE_NUMBER:
            return cursor.var(
                oracledb.DB_TYPE_VARCHAR,
                arraysize=cursor.arraysize,
                outconverter=Decimal,
            )

    rows = {}
    cur.outputtypehandler = decimal_handler
    try:
        for table, columns in CANDIDATE_COLUMNS.items():
            cur.execute(f"select {','.join(columns)} from {table}_stage")
            rows[table] = [dict(zip(columns, r, strict=True)) for r in cur.fetchall()]
    finally:
        cur.outputtypehandler = None
    return rows


def key(row):
    return tuple(row[c] for c in KEY)


def level(value):
    return (
        99
        if value == "RA"
        else int(value)
        if re.fullmatch(r"[0-9]+", value or "")
        else None
    )


def check_stage(rows, manifest, release, reporting_month):
    """Check what the procedure staged without trusting it: keys, scope, rule, months, and every digest."""
    rule = manifest["rule"]
    report = datetime.fromisoformat(reporting_month)
    if (
        manifest.get("schema_version") != 3
        or manifest.get("product") != "REVIEW_CANDIDATES"
        or manifest.get("release") != release
        or manifest.get("reporting_month") != reporting_month
    ):
        raise ValueError("Manifest scope differs from the request")
    if {t: len(r) for t, r in rows.items()} != manifest["rows"]:
        raise ValueError("Stage row counts differ from the manifest")
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
    lower = report.replace(year=report.year - 1)
    for row in rows["review_evidence_month"]:
        k, month = key(row), row["monthly_reporting_period"]
        if k not in months or month.day != 1 or not lower <= month <= report:
            raise ValueError("Orphan or out-of-range monthly evidence")
        if month in months[k]:
            raise ValueError("Duplicate monthly evidence")
        months[k][month] = row
    years = set()
    for k, row in evidence.items():
        candidate = candidates[k]
        if (
            row["rule_version_id"] != rule["rule_version_id"]
            or row["reporting_month"] != report
            or row["data_source"] != "FRE"
            or not re.fullmatch(r"[A-Za-z0-9]{12}", row["loan_identifier"])
            or row["source_release_id"] != release
            or row["rule_code"] != rule["rule_code"]
            or row["version_no"] != rule["version_no"]
            or row["min_delinquency_status"] != rule["min_delinquency_status"]
            or candidate["source_release_id"] != row["source_release_id"]
            or candidate["delinquency_status"] != row["current_loan_delinquency_status"]
        ):
            raise ValueError("Candidate scope or row rule mismatch")
        years.add(int(row["origination_year"]))
        available = months[k]
        if report not in available:
            raise ValueError("Evidence is missing the reporting month")
        if any(row[c] != available[report][c] for c in PERFORMANCE):
            raise ValueError("Reporting-month evidence fields differ")
        expected_missing = []
        for offset in range(12, -1, -1):
            n = report.year * 12 + report.month - 1 - offset
            month = report.replace(year=n // 12, month=n % 12 + 1)
            if month not in available:
                expected_missing.append(month.strftime("%Y-%m-%d"))
        n = report.year * 12 + report.month - 2
        previous = report.replace(year=n // 12, month=n % 12 + 1)
        if (
            (row["missing_months"] or "") != "|".join(expected_missing)
            or row["previous_month_missing"] != str(previous not in available).lower()
            or row["previous_delinquency_status"]
            != available.get(previous, {}).get("current_loan_delinquency_status")
        ):
            raise ValueError("Missing months or previous-month flag mismatch")
        current = level(row["current_loan_delinquency_status"])
        prev = level(row["previous_delinquency_status"]) or 0
        threshold = rule["min_delinquency_status"]
        if current is None or current < threshold or prev >= threshold:
            raise ValueError("Candidate does not satisfy the rule")
        if content_digest(row, list(available.values())) != row["content_sha256"]:
            raise ValueError("Evidence content digest mismatch")
    if manifest["source_years"] != sorted(years):
        raise ValueError("Manifest origination years differ from the evidence")
    if manifest["content_sha256"] != delivery_digest(rows["review_evidence"]):
        raise ValueError("Manifest content digest mismatch")


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
    # All candidate objects (including registration LOBs) are conservatively counted against 160 MiB.
    if used + reserve > 160 * MIB or free is None or free - reserve < 500 * MIB:
        raise SpaceGuardError(
            "Not enough room: candidate 160 MiB budget or at least 500 MiB free in USERS"
        )
    return {"candidate_bytes": used, "users_free_bytes": free}


def merge(cur, delivery, after_merge):
    match = " and ".join("c." + c + "=s." + c for c in KEY)
    cur.execute(f"""merge into review_candidate c using review_candidate_stage s on ({match})
        when matched then update set c.candidate_source='DW'
        when not matched then insert ({",".join(CANDIDATE_COLUMNS["review_candidate"])},candidate_source)
        values ({",".join("s." + c for c in CANDIDATE_COLUMNS["review_candidate"])},'DW')""")
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


def stage(cur, release, reporting_month):
    """Run the PL/SQL selection in this session and return the manifest text."""
    manifest = cur.var(oracledb.DB_TYPE_VARCHAR, 4000)
    cur.callproc(
        "candidate_publish.stage_month",
        [release, datetime.fromisoformat(reporting_month), RULE_CODE, manifest],
    )
    return manifest.getvalue()


def seal(cur, release, reporting_month, rule_version_id):
    """Recompute digests and the manifest from the current stage rows."""
    manifest = cur.var(oracledb.DB_TYPE_VARCHAR, 4000)
    cur.callproc(
        "candidate_publish.seal",
        [release, datetime.fromisoformat(reporting_month), rule_version_id, manifest],
    )
    return manifest.getvalue()


def publish(release, reporting_month, after_merge=lambda _table: None, restage=None):
    """restage(cursor, manifest text) may change the stage rows and return the manifest to publish (tests only)."""
    if not re.fullmatch(r"R[0-9]+", release):
        raise ValueError("Invalid release label")
    first_of_month(reporting_month)
    lockpath = Path(__file__).resolve().parents[1] / "data/locks/candidate_import.lock"
    lockpath.parent.mkdir(parents=True, exist_ok=True)
    with (
        lockpath.open("a") as lock,
        connection() as conn,
        connection() as ledger,
        conn.cursor() as cur,
        ledger.cursor() as lcur,
    ):
        fcntl.flock(lock, fcntl.LOCK_EX)
        # A database row lock also protects runs from different machines; stage tables are session-private temporary tables.
        cur.execute(
            "select lock_id from review_candidate_import_lock where lock_id=1 for update wait 3"
        )
        cur.fetchone()
        text = stage(cur, release, reporting_month)
        if restage:
            text = restage(cur, text)
        sha = hashlib.sha256(text.encode()).hexdigest()
        delivery_hex = sha[:32]
        delivery = bytes.fromhex(delivery_hex)
        lcur.execute(
            "select status,manifest_sha256 from review_candidate_delivery where delivery_id=:d",
            d=delivery,
        )
        prior = lcur.fetchone()
        if prior and prior[1] != sha:
            raise ValueError("Same delivery ID with different content")
        if prior and prior[0] == "PUBLISHED":
            conn.rollback()
            return delivery_hex
        m = json.loads(text)
        # Two in-flight copies of every staged row plus indexes, before anything is registered.
        reserve = (
            m["rows"]["review_evidence"] * 4096
            + m["rows"]["review_evidence_month"] * 1024
            + 4 * MIB
        )
        guard(cur, reserve)
        # The registration is committed on its own connection; a commit here would empty the stage tables.
        if prior:
            lcur.execute(
                "update review_candidate_delivery set status='PREPARING',error_message=null where delivery_id=:d and status!='PUBLISHED'",
                d=delivery,
            )
        else:
            lcur.execute(
                "insert into review_candidate_delivery (delivery_id,manifest_sha256,manifest_json,status) values (:d,:h,:j,'PREPARING')",
                d=delivery,
                h=sha,
                j=text,
            )
        ledger.commit()
        try:
            cur.execute(
                "select status,manifest_sha256 from review_candidate_delivery where delivery_id=:d for update",
                d=delivery,
            )
            status, recorded_sha = cur.fetchone()
            if recorded_sha != sha:
                raise ValueError("Same delivery ID with different content")
            if status == "PUBLISHED":
                conn.rollback()
                return delivery_hex
            if select_rule(cur, reporting_month) != m["rule"]:
                raise ValueError(
                    "Manifest rule version or threshold differs from the database"
                )
            check_stage(read_stage(cur), m, release, reporting_month)
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
            lcur.execute(
                "update review_candidate_delivery set status='FAILED',error_message=:e where delivery_id=:d and status!='PUBLISHED'",
                d=delivery,
                e=message,
            )
            ledger.commit()
            raise
    return delivery_hex


def boundary():
    """Row-by-row digests of existing candidates/cases and every object of this feature, to prove a check left nothing behind."""
    import time

    for attempt in range(5):
        try:
            return snapshot_digests()
        except oracledb.DatabaseError as error:
            # ORA-01466: a table got its first storage segment (deferred segment creation) after the read-only
            # snapshot started, which happens right after the first publication; a new snapshot a moment later reads it.
            if error.args[0].code != 1466 or attempt == 4:
                raise
            time.sleep(2)


def snapshot_digests():
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
            sys.exit(
                "Candidate/evidence/registration/case content changed: the check left residue or rewrote existing data"
            )
        else:
            print(
                "Candidate/evidence/registration/case row digests agree: no test residue"
            )
    elif len(sys.argv) == 3:
        delivery_id = publish(sys.argv[1], sys.argv[2])
        with connection() as conn, conn.cursor() as cur:
            cur.execute(
                "select json_value(manifest_json, '$.rows.review_candidate') from review_candidate_delivery where delivery_id=:d",
                d=bytes.fromhex(delivery_id),
            )
            print(f"Candidates published {delivery_id}: {cur.fetchone()[0]} candidates")
    else:
        sys.exit(__doc__)
