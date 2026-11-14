"""Export the candidate rule parameters (read-only on loan_oltp) for local Spark candidate selection.

Usage: ORACLE_USER=loan_oltp .venv/bin/python python/export_candidate_rule.py YYYY-MM-01
Selection order matches review_api.generate_candidates exactly: effective date descending, then version descending.
Standard output contains only the rule JSON, never connection details.
"""

import json
import sys
from datetime import date
from pathlib import Path

from db import connect

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "spark"))
from candidate_contract import validate_rule


def select_rule(cur, reporting_month):
    month = date.fromisoformat(reporting_month)
    if month.day != 1:
        raise ValueError("The reporting month must be the first day of a month")
    cur.execute(
        """select v.rule_version_id, v.version_no, v.min_delinquency_status,
        v.effective_from from review_rule_version v
        join review_rule r on r.rule_id=v.rule_id
        where r.rule_code=:code and r.is_active='Y' and v.effective_from<=:month
        order by v.effective_from desc, v.version_no desc fetch first 1 row only""",
        code="DLQ60_ENTRY",
        month=month,
    )
    row = cur.fetchone()
    if row is None:
        raise ValueError("No effective DLQ60_ENTRY rule")
    if any(value != int(value) for value in row[:3]):
        raise ValueError("Rule version or threshold is not an integer; export stopped")
    rule = {
        "rule_code": "DLQ60_ENTRY",
        "rule_version_id": int(row[0]),
        "version_no": int(row[1]),
        "min_delinquency_status": int(row[2]),
        "effective_from": row[3].date().isoformat(),
    }
    validate_rule(rule, reporting_month)
    return rule


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with connect() as conn, conn.cursor() as cursor:
        cursor.execute("set transaction read only")
        print(json.dumps(select_rule(cursor, sys.argv[1])))
