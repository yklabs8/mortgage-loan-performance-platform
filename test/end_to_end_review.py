"""End-to-end review walk-through over HTTP against the running web application (it commits; run it only on the end-to-end database).

Usage: .venv/bin/python test/end_to_end_review.py <base URL> <reporting month YYYY-MM-01>
For example: .venv/bin/python test/end_to_end_review.py http://localhost:8091 2009-06-01
Requires: candidates published for the month (python/candidate_import.py); demo passwords in app/demo-users.local.txt
(scripts/11_set_demo_passwords.sh); the application started with scripts/12_run_app.sh.
Steps, each through the real login, CSRF token, and least-privilege web account: the analyst opens a case on one published candidate,
the manager assigns it to the analyst, the analyst adds a note, the manager escalates it and then closes it.
Prints the case ID; the database must show it CLOSED and still pinned to the evidence it was opened with.
"""

import http.cookiejar
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

ROOT = Path(__file__).resolve().parents[1]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Browser:
    """One signed-in user: a cookie jar, and redirects reported instead of followed."""

    def __init__(self, base, username, password):
        self.base = base
        jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar), NoRedirect
        )
        status, location = self.post(
            "/login", "/login", username=username, password=password
        )
        if status != 302 or "error" in location:
            raise RuntimeError(f"Sign-in failed for {username}")

    def get(self, path):
        with self.opener.open(self.base + path) as response:
            return response.read().decode()

    def post(self, page, path, **fields):
        token = re.search(r'name="_csrf" value="([^"]+)"', self.get(page))
        if not token:
            raise RuntimeError(f"No CSRF token on {page}")
        data = urllib.parse.urlencode({**fields, "_csrf": token.group(1)}).encode()
        try:
            self.opener.open(self.base + path, data)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise
            return error.code, error.headers.get("Location", "")
        raise RuntimeError(f"{path} did not redirect")


def main(base, month):
    from candidate_import import connection

    passwords = dict(
        line.split()
        for line in (ROOT / "app/demo-users.local.txt").read_text().splitlines()
        if line and not line.startswith("#")
    )
    with connection() as conn, conn.cursor() as cur:
        cur.execute(
            """select c.candidate_id, c.latest_evidence_id from review_candidate c
            where c.reporting_month=:m and c.candidate_source='DW' and c.latest_evidence_id is not null
            and not exists (select 1 from risk_review_case r where r.candidate_id=c.candidate_id)
            order by c.loan_identifier fetch first 1 row only""",
            m=datetime.fromisoformat(month),
        )
        row = cur.fetchone()
        if row is None:
            raise SystemExit(f"No published candidate without a case for {month}")
        candidate_id, evidence_id = row
        cur.execute("select user_id from app_user where username='analyst_demo'")
        analyst_id = cur.fetchone()[0]

    analyst = Browser(base, "analyst_demo", passwords["analyst_demo"])
    manager = Browser(base, "manager_demo", passwords["manager_demo"])
    _, location = analyst.post(
        f"/candidates/{candidate_id}", f"/candidates/{candidate_id}/open"
    )
    case = re.fullmatch(r".*/cases/(\d+)", location)
    if not case:
        raise RuntimeError(
            f"Opening the case did not lead to the case page: {location}"
        )
    case_id = int(case.group(1))
    page = f"/cases/{case_id}"
    manager.post(page, f"{page}/assign", assigneeUserId=analyst_id)
    analyst.post(
        page, f"{page}/annotate", noteText="End-to-end check: entered 60+ this month"
    )
    for decision, expected in [("ESCALATE", "IN_REVIEW"), ("CLOSE", "ESCALATED")]:
        manager.post(
            page,
            f"{page}/decide",
            expectedStatus=expected,
            decisionType=decision,
            decisionNote="End-to-end check",
            confirmed="true",
        )
    with connection() as conn, conn.cursor() as cur:
        cur.execute(
            "select current_status, evidence_id from risk_review_case where case_id=:c",
            c=case_id,
        )
        status, pinned = cur.fetchone()
        cur.execute(
            "select listagg(to_status, '>') within group (order by changed_at, status_event_id) from case_status_history where case_id=:c",
            c=case_id,
        )
        path = cur.fetchone()[0]
    if status != "CLOSED" or pinned != evidence_id:
        raise SystemExit(
            f"Case {case_id}: status {status}, evidence {pinned} (expected CLOSED, {evidence_id})"
        )
    print(
        f"Case {case_id} for candidate {candidate_id}: {path}; pinned evidence {pinned}"
    )
    return case_id


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
