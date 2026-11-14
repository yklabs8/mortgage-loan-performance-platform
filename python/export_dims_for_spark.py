"""Export the three shared dimension tables from Oracle to CSV for Spark.

Usage: python python/export_dims_for_spark.py <output dir> [<release> <source year>]
For example: python python/export_dims_for_spark.py spark/reference
      python python/export_dims_for_spark.py /tmp/sample_input R47 2010
With a release and source year, it also exports the inputs of sample candidate selection (spark/sample_candidates.py): that year's loan dimension,
monthly detail, and the release's latest quality check, with column order taken from spark/candidate_contract.py rather than defined again.
Why not rewrite them in Spark: a dimension may have only one definition,
and the delinquency bands and exit destinations are defined only in Oracle's load_dim_*.sql; Spark reads the files exported here.
Re-export after a dimension changes (the files are in git, so changes are visible).
Requires: python/db.py. Called by: run manually.
"""

import csv  # write CSV
import os  # create the output directory
import sys  # read command-line arguments
from datetime import datetime  # dates written as YYYY-MM-DD
from decimal import Decimal  # numbers written exactly, never through floating point
from pathlib import Path

import oracledb

from db import connect  # database connection

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "spark"))
from candidate_contract import ORIGIN, PERFORMANCE
from delivery_contract import DQ_COLUMNS, REQUIRED_RULES

QUERIES = {  # file name -> query (ordered by primary key, so results are stable and git diffs readable)
    "dim_delinquency_status.csv": (
        "select status_code, dlq_state, dlq_state_order, is_dlq60"
        " from dim_delinquency_status order by status_code"
    ),
    "dim_zero_balance_code.csv": (
        "select data_source, zero_balance_code, zero_balance_desc, exit_state,"
        " exit_state_order from dim_zero_balance_code"
        " order by data_source, zero_balance_code"
    ),
    "dim_geography.csv": (
        "select state_code, census_region_name from dim_geography order by state_code"
    ),
}


# Sample candidate inputs: one release and one source year only (origination year derived from the loan number in the Oracle sample)
SAMPLE_QUERIES = {
    "dim_loan.csv": (
        "select data_source, loan_identifier, "
        + ", ".join(ORIGIN)
        + " from dim_loan where release_id = :r and origination_year = :y"
        " order by data_source, loan_identifier"
    ),
    "dwd_loan_monthly_perf.csv": (
        "select p.data_source, p.loan_identifier, p.monthly_reporting_period, "
        + ", ".join("p." + c for c in PERFORMANCE)
        + " from dwd_loan_monthly_perf p join dim_loan d"
        " on d.data_source = p.data_source and d.loan_identifier = p.loan_identifier"
        " and d.release_id = p.release_id"
        " where p.release_id = :r and d.origination_year = :y"
        " order by p.data_source, p.loan_identifier, p.monthly_reporting_period"
    ),
}
# Spark checks each source year separately; the Oracle sample checks a release as a whole (checks/dq_ods.sql, dq_dw.sql).
# The issue count of the whole release is attributed to this year: it can only over-report, never under-report, and a FAIL in any year blocks the delivery.
# Checked row counts are this year's exported rows (same as Spark: DQ003 and DQ004B count origination rows, the rest count monthly rows).
DQ_QUERY = (
    "select rule_id, dw_layer, severity, bad_count, checked_at from dq_check_latest"
    " where release_id = :r and rule_id in ("
    + ", ".join(f"'{r}'" for r in sorted(REQUIRED_RULES))
    + ") order by rule_id"
)
WARN_RULES = {
    "DQ004B",
    "DQ007B",
    "DQ008",
    "DQ009",
}  # same as delivery_contract.quality_status
QUARANTINE_RULES = {"DQ004", "DQ006"}  # continue after quarantine; a non-zero issue count is recorded as WARN


def text(value):  # write one cell as text Spark can convert strictly; nulls are written empty
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, Decimal):
        return format(value, "f")
    return value


def write_rows(path, header, rows):  # write CSV, return the row count
    count = 0
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        for row in rows:
            writer.writerow([text(v) for v in row])
            count += 1
    return count


def export(
    out_dir, release=None, year=None
):  # export dimensions (and sample candidate inputs), return row counts per file
    os.makedirs(out_dir, exist_ok=True)  # create the output directory if missing
    counts = {}
    with connect() as conn, conn.cursor() as cur:
        for name, sql in QUERIES.items():
            cur.execute(sql)
            header = [d[0].lower() for d in cur.description]  # column names
            rows = cur.fetchall()
            with open(
                os.path.join(out_dir, name), "w", encoding="utf-8", newline=""
            ) as f:
                writer = csv.writer(f)
                writer.writerow(header)
                writer.writerows(rows)
            counts[name] = len(rows)
            print(f"{name}: {len(rows)} rows")
        if release is None:
            return counts
        cur.execute("set transaction read only")  # all tables read as of the same moment
        cur.arraysize = 10000
        cur.outputtypehandler = decimal_handler
        for name, sql in SAMPLE_QUERIES.items():
            cur.execute(sql, r=release, y=int(year))
            header = [d[0].lower() for d in cur.description]
            counts[name] = write_rows(os.path.join(out_dir, name), header, cur)
            print(f"{name}: {counts[name]} rows")
        if not counts["dim_loan.csv"]:
            raise ValueError(f"{release} has no loans from {year}")
        cur.execute(DQ_QUERY, r=release)
        rows = []
        for rule, layer, severity, bad, checked_at in cur.fetchall():
            status = (
                "PASS"
                if bad == 0
                else "WARN"
                if rule in WARN_RULES | QUARANTINE_RULES
                else "FAIL"
            )
            checked = counts[
                "dim_loan.csv"
                if rule in {"DQ003", "DQ004B"}
                else "dwd_loan_monthly_perf.csv"
            ]
            rows.append(
                (
                    rule,
                    layer,
                    severity,
                    checked,
                    bad,
                    status,
                    checked_at.isoformat(),
                    int(year),
                )
            )
        conn.rollback()
        if {r[0] for r in rows} != REQUIRED_RULES:
            raise ValueError(f"{release} is missing check results for required quality rules")
        counts["dq_check_result.csv"] = write_rows(
            os.path.join(out_dir, "dq_check_result.csv"), DQ_COLUMNS, rows
        )
        print(f"dq_check_result.csv: {len(rows)} rows")
    return counts


def decimal_handler(cursor, metadata):  # fetch numbers as Decimal, never through floating point
    if metadata.type_code is oracledb.DB_TYPE_NUMBER:
        return cursor.var(
            oracledb.DB_TYPE_VARCHAR, arraysize=cursor.arraysize, outconverter=Decimal
        )


if __name__ == "__main__":
    if len(sys.argv) not in (2, 4):  # wrong arguments
        sys.exit(__doc__)
    export(*sys.argv[1:])
