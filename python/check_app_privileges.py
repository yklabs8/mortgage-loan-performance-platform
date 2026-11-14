"""Create a dedicated TEST candidate, then run the privilege assertions as loan_app; finally clean only this run's candidate.

Usage: .venv/bin/python python/check_app_privileges.py. Called by the web account creation script.
Does not call the reference generation procedure and opens no case; the privilege SQL rolls back its own business writes.
"""

import os
import subprocess
import uuid
from pathlib import Path

from candidate_import import connection
from database_target import require_test

ROOT = Path(__file__).resolve().parents[1]


def run():
    with connection() as conn, conn.cursor() as cur:
        require_test(conn)
        cur.execute(
            """insert into review_candidate (rule_version_id, data_source,
            loan_identifier, reporting_month, delinquency_status, source_release_id,
            candidate_source) values (1,'FRE',:loan,date '2020-06-01','02','R47','TEST')
            returning candidate_id into :id""",
            loan="T" + uuid.uuid4().hex[:11],
            id=(key := cur.var(int)),
        )
        candidate = key.getvalue()[0]
        conn.commit()
        try:
            subprocess.run(
                [
                    "scripts/run_sql.sh",
                    "test/test_app_user_privileges.sql",
                    "owner=loan_oltp",
                    f"candidate_id={candidate}",
                ],
                cwd=ROOT,
                env=dict(os.environ, ORACLE_USER="loan_app"),
                check=True,
            )
        finally:
            cur.execute(
                "delete from review_candidate where candidate_id=:id and candidate_source='TEST'",
                id=candidate,
            )
            conn.commit()


if __name__ == "__main__":
    run()
