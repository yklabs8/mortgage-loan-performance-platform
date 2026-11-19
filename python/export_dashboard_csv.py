"""Export the analysis tables of one release to CSV for the Tableau dashboards, in one read-only transaction.

Usage: .venv/bin/python python/export_dashboard_csv.py <release> <output directory>
For example: .venv/bin/python python/export_dashboard_csv.py R47 dashboards/data
Then: python3 dashboards/build_dashboards.py dashboards/data dashboards/loan_risk_dashboards.twb
Writes one <table>.csv per analysis table with a header row; columns follow the table definition, without the release label;
rows are in a fixed order, so the same data always gives byte-identical files.
"""

import csv
import sys
from pathlib import Path

from db import connect

TABLES = [
    "ads_vintage_dlq60_curve",
    "ads_vintage_dlq60_segment",
    "ads_dlq_transition_monthly",
    "ads_modification_outcome",
    "ads_modification_segment",
    "ads_cure_redefault_segment",
    "ads_final_outcome_segment",
]
SKIP = {"RELEASE_ID"}


def cell(value):
    if value is None:
        return ""
    if hasattr(value, "strftime"):
        return value.strftime("%Y-%m-%d")
    return str(value)


def main(release, folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    with connect() as conn, conn.cursor() as cur:
        cur.execute("set transaction read only")
        for table in TABLES:
            cur.execute(
                "select column_name from user_tab_columns where table_name=:t order by column_id",
                t=table.upper(),
            )
            columns = [r[0] for r in cur.fetchall() if r[0] not in SKIP]
            order = ",".join(str(i + 1) for i in range(len(columns)))
            cur.execute(
                f"select {','.join(columns)} from {table} where release_id=:r order by {order}",
                r=release,
            )
            rows = cur.fetchall()
            if not rows:
                raise SystemExit(f"{table} has no rows for {release}")
            with (folder / f"{table}.csv").open("w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow([c.lower() for c in columns])
                writer.writerows([cell(v) for v in row] for row in rows)
            print(f"{table}: {len(rows)} rows")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
