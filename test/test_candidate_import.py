"""Oracle candidate import acceptance; random business keys, cleaning only objects created by each case."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))


class CandidateImportSchemaTest(unittest.TestCase):
    def test_importer_and_schema(self):
        import candidate_import

        with candidate_import.connection() as conn, conn.cursor() as cur:
            for name in candidate_import.BUSINESS_TABLES + [
                "review_candidate_delivery"
            ]:
                cur.execute(
                    "select count(*) from user_tables where table_name=:n",
                    n=name.upper(),
                )
                self.assertEqual(cur.fetchone()[0], 1, name)


class CandidatePublicationTest(unittest.TestCase):
    def setUp(self):
        import uuid

        import candidate_import as p
        from database_target import require_test

        with p.connection() as conn:
            require_test(conn)
        self.p = p
        self.loan = "T" + uuid.uuid4().hex[:11].upper()
        self.deliveries = []
        self.addCleanup(self.clean)

    def clean(self):
        with self.p.connection() as conn, conn.cursor() as cur:
            cur.execute(
                "select candidate_id from review_candidate where loan_identifier=:l",
                l=self.loan,
            )
            ids = [r[0] for r in cur.fetchall()]
            for cid in ids:
                cur.execute(
                    "select case_id from risk_review_case where candidate_id=:c", c=cid
                )
                for (case_id,) in cur.fetchall():
                    cur.execute(
                        "delete from case_status_history where case_id=:c", c=case_id
                    )
                    cur.execute(
                        "delete from risk_review_case where case_id=:c", c=case_id
                    )
                cur.execute(
                    "update review_candidate set latest_evidence_id=null where candidate_id=:c",
                    c=cid,
                )
                cur.execute(
                    "delete from review_evidence_month where evidence_id in (select evidence_id from review_evidence where candidate_id=:c)",
                    c=cid,
                )
                cur.execute("delete from review_evidence where candidate_id=:c", c=cid)
                cur.execute("delete from review_candidate where candidate_id=:c", c=cid)
            for d in self.deliveries:
                cur.execute(
                    "delete from review_candidate_delivery where delivery_id=:d",
                    d=bytes.fromhex(d),
                )
            conn.commit()
            for t in self.p.BUSINESS_TABLES[3:]:
                cur.execute(f"select count(*) from {t}")
                self.assertEqual(cur.fetchone()[0], 0)

    def package(self, amount="123.45678901", zero=False, rule_change=None, mutate=None):
        import csv
        import tempfile

        import candidate_contract as c
        from delivery_contract import DQ_COLUMNS, REQUIRED_RULES
        from export_candidate_rule import select_rule

        with self.p.connection() as conn, conn.cursor() as cur:
            rule = select_rule(cur, "2020-06-01")
        if rule_change:
            rule.update(rule_change)
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        folder = Path(temp.name)
        base = {
            "rule_version_id": str(rule["rule_version_id"]),
            "data_source": "FRE",
            "loan_identifier": self.loan,
            "reporting_month": "2020-06-01",
        }
        candidate = {**base, "delinquency_status": "02", "source_release_id": "R47"}
        row = {k: "" for k in c.CANDIDATE_COLUMNS["review_evidence"]}
        row.update(base)
        row.update(
            source_release_id="R47",
            rule_code=rule["rule_code"],
            version_no=str(rule["version_no"]),
            min_delinquency_status=str(rule["min_delinquency_status"]),
            classic_fico="700.00000000",
            original_upb="100000.00000000",
            original_loan_to_value_ltv="80.00000000",
            original_interest_rate="4.00000000",
            property_state="NY",
            origination_year="2010",
            first_payment_date="2010-06-01",
            current_loan_delinquency_status="02",
            current_actual_upb=amount,
            current_interest_rate="3.25000000",
            previous_month_missing="true",
            missing_months="|".join(
                f"{y}-{m:02d}-01"
                for y, m in [(2019, m) for m in range(6, 13)]
                + [(2020, m) for m in range(1, 6)]
            ),
        )
        monthly = {
            k: row.get(k, "") for k in c.CANDIDATE_COLUMNS["review_evidence_month"]
        }
        monthly["monthly_reporting_period"] = "2020-06-01"
        row["content_sha256"] = self.p.content_digest(row, [monthly])
        data = {
            "review_candidate": [candidate],
            "review_evidence": [row],
            "review_evidence_month": [monthly],
        }
        if mutate:
            mutate(data)
        for t, cols in c.CANDIDATE_COLUMNS.items():
            (folder / t).mkdir()
            with (folder / t / "part-000.csv").open("w", newline="") as f:
                w = csv.DictWriter(f, fieldnames=cols)
                w.writeheader()
                if not zero:
                    w.writerows(data[t])
        with (folder / "dq_check_result.csv").open("w", newline="") as f:
            w = csv.writer(f)
            w.writerow(DQ_COLUMNS)
            for r in REQUIRED_RULES:
                w.writerow(
                    [
                        r,
                        "ODS",
                        "WARN"
                        if r in {"DQ004B", "DQ007B", "DQ008", "DQ009"}
                        else "HARD",
                        1,
                        0,
                        "PASS",
                        "2026-10-19T00:00:00Z",
                        2010,
                    ]
                )
        m = c.build_candidate_manifest(
            folder,
            "sample",
            "R47",
            [2010],
            "a" * 40,
            False,
            rule,
            "2020-06-01",
            "b" * 32,
            "c" * 64,
        )
        self.deliveries.append(m["delivery_id"])
        return folder

    def snapshot(self):
        result = {}
        with self.p.connection() as conn, conn.cursor() as cur:
            for t, sql in {
                "candidate": "select candidate_id, candidate_source, latest_evidence_id, delinquency_status, source_release_id from review_candidate where loan_identifier=:l",
                "evidence": "select evidence_id,candidate_id,rawtohex(delivery_id),content_sha256 from review_evidence where loan_identifier=:l order by evidence_id",
                "month": "select m.evidence_id,m.monthly_reporting_period,m.current_actual_upb from review_evidence_month m join review_evidence e on e.evidence_id=m.evidence_id where e.loan_identifier=:l order by m.evidence_id,m.monthly_reporting_period",
                "case": "select c.case_id,c.evidence_id from risk_review_case c join review_candidate r on r.candidate_id=c.candidate_id where r.loan_identifier=:l",
            }.items():
                cur.execute(sql, l=self.loan)
                result[t] = cur.fetchall()
        return result

    def status(self, d):
        with self.p.connection() as conn, conn.cursor() as cur:
            cur.execute(
                "select status,error_message from review_candidate_delivery where delivery_id=:d",
                d=bytes.fromhex(d),
            )
            return cur.fetchone()

    def test_repeat_and_same_content_new_delivery(self):
        folder = self.package()
        self.p.publish(folder)
        before = self.snapshot()
        self.p.publish(folder)
        self.assertEqual(self.snapshot(), before)
        second = self.package()
        self.p.publish(second)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.status(self.deliveries[-1]), ("PUBLISHED", None))
        self.assertEqual(
            [len(before[k]) for k in ["candidate", "evidence", "month"]], [1, 1, 1]
        )

    def test_new_evidence_keeps_case_reference(self):
        self.p.publish(self.package())
        before = self.snapshot()
        cid, _, old_evidence, *_ = before["candidate"][0]
        with self.p.connection() as conn, conn.cursor() as cur:
            cur.execute("select min(user_id) from app_user where is_active='Y'")
            user = cur.fetchone()[0]
            cur.execute(
                "insert into risk_review_case (case_number,candidate_id,opened_by_user_id,updated_by_user_id,evidence_id) values (:n,:c,:u,:u,:e)",
                n=self.loan,
                c=cid,
                u=user,
                e=old_evidence,
            )
            conn.commit()
        self.p.publish(self.package(amount="0.00000000"))
        after = self.snapshot()
        self.assertEqual(after["candidate"][0][0], cid)
        self.assertNotEqual(after["candidate"][0][2], old_evidence)
        self.assertEqual(after["case"][0][1], old_evidence)
        self.assertEqual(
            [len(after[k]) for k in ["candidate", "evidence", "month"]], [1, 2, 2]
        )

    def test_month_merge_failure_rolls_back_everything_and_retry(self):
        self.p.publish(self.package())
        before = self.snapshot()
        folder = self.package(amount="42.00000000")

        def fail(table):
            if table == "review_evidence_month":
                raise RuntimeError("deliberate failure while merging monthly evidence")

        with self.assertRaisesRegex(RuntimeError, "monthly evidence"):
            self.p.publish(folder, after_merge=fail)
        self.assertEqual(self.snapshot(), before)
        state, error = self.status(self.deliveries[-1])
        self.assertEqual(state, "FAILED")
        self.assertIn("monthly evidence", error)
        self.p.publish(folder)
        self.assertEqual(len(self.snapshot()["evidence"]), 2)

    def test_database_rule_mismatch(self):
        for change in [
            {"min_delinquency_status": 3},
            {"version_no": 99},
            {"rule_version_id": 999999},
        ]:
            folder = self.package(rule_change=change)
            with self.assertRaisesRegex(ValueError, "rule version or threshold"):
                self.p.publish(folder)
            self.assertEqual(self.snapshot()["candidate"], [])
            self.assertEqual(self.status(self.deliveries[-1])[0], "FAILED")

    def test_zero_candidates_published(self):
        self.p.publish(self.package(zero=True))
        self.assertEqual(self.status(self.deliveries[-1]), ("PUBLISHED", None))
        self.assertTrue(all(not v for v in self.snapshot().values()))

    def test_existing_sample_identity_business_fields_preserved(self):
        from export_candidate_rule import select_rule

        with self.p.connection() as conn, conn.cursor() as cur:
            rule = select_rule(cur, "2020-06-01")
            cur.execute(
                "insert into review_candidate (rule_version_id,data_source,loan_identifier,reporting_month,delinquency_status,source_release_id) values (:r,'FRE',:l,date '2020-06-01','03','R46')",
                r=rule["rule_version_id"],
                l=self.loan,
            )
            conn.commit()
        before = self.snapshot()["candidate"][0]
        self.p.publish(self.package())
        after = self.snapshot()["candidate"][0]
        self.assertEqual(after[0], before[0])
        self.assertEqual(after[1], "SPARK")
        self.assertEqual(after[3:], before[3:])

    def test_business_tampering_rejected_even_with_new_file_hash(self):
        cases = [
            lambda d: d["review_evidence"][0].update(content_sha256="0" * 64),
            lambda d: d["review_evidence_month"][0].update(current_actual_upb="99"),
            lambda d: d["review_evidence_month"][0].update(
                monthly_reporting_period="2019-01-01"
            ),
            lambda d: d["review_candidate"][0].update(loan_identifier="T00000000000"),
            lambda d: d["review_evidence"][0].update(previous_month_missing="false"),
        ]
        for mutate in cases:
            folder = self.package(mutate=mutate)
            with self.assertRaises(ValueError):
                self.p.publish(folder)
            self.assertFalse(self.snapshot()["candidate"])
            self.assertEqual(self.status(self.deliveries[-1])[0], "FAILED")

    def test_space_guard_rejects_without_writes(self):
        with (
            self.p.connection() as conn,
            conn.cursor() as cur,
            self.assertRaisesRegex(ValueError, "budget"),
        ):
            self.p.guard(cur, 161 * self.p.MIB)
        self.assertFalse(self.snapshot()["candidate"])

    def test_two_independent_importers_keep_publication_immutable(self):
        import threading
        from concurrent.futures import ThreadPoolExecutor
        from unittest.mock import patch

        folder = self.package()
        written = threading.Event()
        release = threading.Event()
        second_attempt = threading.Event()
        callbacks = []
        real_connection = self.p.connection

        class Cursor:
            def __init__(self, cur):
                self.cur = cur

            def __getattr__(self, name):
                return getattr(self.cur, name)

            def __setattr__(self, name, value):
                if name == "cur":
                    object.__setattr__(self, name, value)
                else:
                    setattr(self.cur, name, value)

            def __enter__(self):
                self.cur.__enter__()
                return self

            def __exit__(self, *args):
                return self.cur.__exit__(*args)

            def execute(self, sql, *args, **kwargs):
                second = threading.current_thread().name.endswith("_1")
                if second and "review_candidate_import_lock" in sql:
                    second_attempt.set()
                result = self.cur.execute(sql, *args, **kwargs)
                if second and "select status,manifest_sha256" in sql:
                    second_attempt.set()
                return result

        class Conn:
            def __init__(self):
                self.conn = real_connection()

            def __getattr__(self, name):
                return getattr(self.conn, name)

            def cursor(self):
                return Cursor(self.conn.cursor())

            def __enter__(self):
                self.conn.__enter__()
                return self

            def __exit__(self, *args):
                return self.conn.__exit__(*args)

        def pause(table):
            if table == "review_evidence_month":
                written.set()
                if not release.wait(5):
                    raise RuntimeError("test wait timed out")

        # Disable the local flock to simulate two different checkouts; the real Oracle lock stays.
        with (
            patch.object(self.p.fcntl, "flock"),
            patch.object(self.p, "connection", Conn),
            ThreadPoolExecutor(2, thread_name_prefix="candidate") as pool,
        ):
            a = pool.submit(self.p.publish, folder, after_merge=pause)
            try:
                self.assertTrue(written.wait(3))
                b = pool.submit(self.p.publish, folder, after_merge=callbacks.append)
                self.assertTrue(second_attempt.wait(3))
                self.assertFalse(b.done())
            finally:
                release.set()
            self.assertEqual(a.result(timeout=5), b.result(timeout=5))
        self.assertEqual(callbacks, [], "A published delivery was merged again")
        self.assertEqual(len(self.snapshot()["evidence"]), 1)
        self.assertEqual(self.status(self.deliveries[-1]), ("PUBLISHED", None))


def setUpModule():
    """Before any fixture or failure cleanup in this module, verify the real database environment."""
    from db import connect_test_database

    connect_test_database().close()
