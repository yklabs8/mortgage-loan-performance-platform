"""Oracle candidate selection and publication acceptance; runs only on a database marked TEST.

CandidatePublicationTest replaces the staged rows with one made-up loan (random business key) and cleans only what each case created.
CandidateSelectionTest applies the rule to the loaded warehouse for one month and compares it with an independent count.
"""

import sys
import unittest
from datetime import datetime
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

MONTH = "2020-06-01"
RELEASE = "R47"


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
            cur.execute(
                "select status from user_objects where object_name='CANDIDATE_PUBLISH' and object_type='PACKAGE BODY'"
            )
            self.assertEqual(cur.fetchone(), ("VALID",))


def clean_candidates(cur, where, **binds):
    cur.execute(f"select candidate_id from review_candidate where {where}", binds)
    for (cid,) in cur.fetchall():
        cur.execute("select case_id from risk_review_case where candidate_id=:c", c=cid)
        for (case_id,) in cur.fetchall():
            cur.execute("delete from case_status_history where case_id=:c", c=case_id)
            cur.execute("delete from risk_review_case where case_id=:c", c=case_id)
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
            clean_candidates(cur, "loan_identifier=:l", l=self.loan)
            for d in set(self.deliveries):
                cur.execute(
                    "delete from review_candidate_delivery where delivery_id=:d",
                    d=bytes.fromhex(d),
                )
            conn.commit()

    def restage(self, amount="123.450", status="02", previous=None, tamper=None):
        """Replace what stage_month staged with one made-up candidate, then seal it (tamper runs after sealing)."""

        def run(cur, _text):
            rule = self.p.select_rule(cur, MONTH)
            for t in ["review_evidence_month", "review_evidence", "review_candidate"]:
                cur.execute(f"delete from {t}_stage")
            key = {
                "r": rule["rule_version_id"],
                "l": self.loan,
                "m": datetime.fromisoformat(MONTH),
            }
            cur.execute(
                "insert into review_candidate_stage values (:r,'FRE',:l,:m,:s,'R47')",
                **key,
                s=status,
            )
            months = [(MONTH, status, Decimal(amount))]
            if previous:
                months.append(("2020-05-01", previous, Decimal("99.000")))
            for period, code, upb in months:
                cur.execute(
                    """insert into review_evidence_month_stage values
                    (:r,'FRE',:l,:m,:p,:s,:u,3.25,null,null,null)""",
                    **key,
                    p=datetime.fromisoformat(period),
                    s=code,
                    u=upb,
                )
            missing = [
                f"{y}-{m:02d}-01"
                for y, m in [(2019, m) for m in range(6, 13)]
                + [(2020, m) for m in range(1, 6)]
                if not (previous and (y, m) == (2020, 5))
            ]
            cur.execute(
                """insert into review_evidence_stage (rule_version_id,data_source,loan_identifier,reporting_month,
                source_release_id,rule_code,version_no,min_delinquency_status,classic_fico,original_upb,
                original_loan_to_value_ltv,original_interest_rate,property_state,origination_year,first_payment_date,
                current_loan_delinquency_status,current_actual_upb,current_interest_rate,previous_delinquency_status,
                previous_month_missing,missing_months)
                values (:r,'FRE',:l,:m,'R47',:code,:v,:t,700,100000,80,4,'NY',2010,date '2010-06-01',:s,:u,3.25,:prev,:pm,:mm)""",
                **key,
                code=rule["rule_code"],
                v=rule["version_no"],
                t=rule["min_delinquency_status"],
                s=status,
                u=Decimal(amount),
                prev=previous,
                pm="false" if previous else "true",
                mm="|".join(missing),
            )
            text = self.p.seal(cur, RELEASE, MONTH, rule["rule_version_id"])
            if tamper:
                tamper(cur)
            import hashlib

            self.deliveries.append(hashlib.sha256(text.encode()).hexdigest()[:32])
            return text

        return run

    def publish(self, **kwargs):
        after_merge = kwargs.pop("after_merge", lambda _t: None)
        return self.p.publish(
            RELEASE, MONTH, after_merge=after_merge, restage=self.restage(**kwargs)
        )

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

    def test_repeat_is_a_no_op(self):
        first = self.publish()
        before = self.snapshot()
        self.assertEqual(self.publish(), first)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.status(first), ("PUBLISHED", None))
        self.assertEqual(before["candidate"][0][1], "DW")
        self.assertEqual(
            [len(before[k]) for k in ["candidate", "evidence", "month"]], [1, 1, 1]
        )

    def test_new_evidence_keeps_case_reference(self):
        self.publish()
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
        self.publish(amount="0", previous="01")
        after = self.snapshot()
        self.assertEqual(after["candidate"][0][0], cid)
        self.assertNotEqual(after["candidate"][0][2], old_evidence)
        self.assertEqual(after["case"][0][1], old_evidence)
        self.assertEqual(
            [len(after[k]) for k in ["candidate", "evidence", "month"]], [1, 2, 3]
        )

    def test_month_merge_failure_rolls_back_everything_and_retry(self):
        self.publish()
        before = self.snapshot()

        def fail(table):
            if table == "review_evidence_month":
                raise RuntimeError("deliberate failure while merging monthly evidence")

        with self.assertRaisesRegex(RuntimeError, "monthly evidence"):
            self.publish(amount="42", after_merge=fail)
        self.assertEqual(self.snapshot(), before)
        state, error = self.status(self.deliveries[-1])
        self.assertEqual(state, "FAILED")
        self.assertIn("monthly evidence", error)
        self.publish(amount="42")
        self.assertEqual(self.status(self.deliveries[-1]), ("PUBLISHED", None))
        self.assertEqual(len(self.snapshot()["evidence"]), 2)

    def test_zero_candidates_published(self):
        def empty(cur, _text):
            rule = self.p.select_rule(cur, MONTH)
            for t in ["review_evidence_month", "review_evidence", "review_candidate"]:
                cur.execute(f"delete from {t}_stage")
            text = self.p.seal(cur, RELEASE, MONTH, rule["rule_version_id"])
            import hashlib

            self.deliveries.append(hashlib.sha256(text.encode()).hexdigest()[:32])
            return text

        self.p.publish(RELEASE, MONTH, restage=empty)
        self.assertEqual(self.status(self.deliveries[-1]), ("PUBLISHED", None))
        self.assertTrue(all(not v for v in self.snapshot().values()))

    def test_existing_reference_candidate_keeps_identity_and_business_fields(self):
        with self.p.connection() as conn, conn.cursor() as cur:
            rule = self.p.select_rule(cur, MONTH)
            cur.execute(
                "insert into review_candidate (rule_version_id,data_source,loan_identifier,reporting_month,delinquency_status,source_release_id) values (:r,'FRE',:l,date '2020-06-01','03','R46')",
                r=rule["rule_version_id"],
                l=self.loan,
            )
            conn.commit()
        before = self.snapshot()["candidate"][0]
        self.publish()
        after = self.snapshot()["candidate"][0]
        self.assertEqual(after[0], before[0])
        self.assertEqual(after[1], "DW")
        self.assertEqual(after[3:], before[3:])

    def test_tampering_after_sealing_is_rejected(self):
        cases = [
            "update review_evidence_stage set content_sha256=lpad('0',64,'0')",
            "update review_evidence_month_stage set current_actual_upb=99",
            "update review_evidence_month_stage set monthly_reporting_period=date '2019-01-01'",
            "update review_candidate_stage set delinquency_status='03'",
            "update review_evidence_stage set previous_month_missing='false'",
            "update review_evidence_stage set origination_year=2011",
        ]
        for sql in cases:
            with self.subTest(sql=sql), self.assertRaises(ValueError):
                self.publish(tamper=lambda cur, sql=sql: cur.execute(sql))
            self.assertFalse(self.snapshot()["candidate"])
            self.assertEqual(self.status(self.deliveries[-1])[0], "FAILED")

    def test_candidate_below_threshold_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "does not satisfy the rule"):
            self.publish(status="01")
        self.assertFalse(self.snapshot()["candidate"])

    def test_space_guard_rejects_without_writes(self):
        with (
            self.p.connection() as conn,
            conn.cursor() as cur,
            self.assertRaisesRegex(ValueError, "budget"),
        ):
            self.p.guard(cur, 161 * self.p.MIB)
        self.assertFalse(self.snapshot()["candidate"])

    def test_two_independent_runs_publish_once(self):
        import threading
        import time
        from concurrent.futures import ThreadPoolExecutor
        from unittest.mock import patch

        written = threading.Event()
        release = threading.Event()
        callbacks = []

        def pause(table):
            if table == "review_evidence_month":
                written.set()
                if not release.wait(5):
                    raise RuntimeError("test wait timed out")

        # Disable the local file lock to simulate two different checkouts; the Oracle row lock stays.
        with (
            patch.object(self.p.fcntl, "flock"),
            ThreadPoolExecutor(2) as pool,
        ):
            a = pool.submit(self.publish, after_merge=pause)
            try:
                self.assertTrue(written.wait(10))
                b = pool.submit(self.publish, after_merge=callbacks.append)
                time.sleep(1)
                self.assertFalse(b.done())
            finally:
                release.set()
            self.assertEqual(a.result(timeout=10), b.result(timeout=10))
        self.assertEqual(callbacks, [], "A published delivery was merged again")
        self.assertEqual(len(self.snapshot()["evidence"]), 1)


class CandidateSelectionTest(unittest.TestCase):
    """The procedure against the loaded warehouse: the same candidates as an independent count, digests checked, a repeat changes nothing."""

    month = "2009-03-01"

    def setUp(self):
        import candidate_import as p
        from database_target import require_test

        self.p = p
        with p.connection() as conn, conn.cursor() as cur:
            require_test(conn)
            cur.execute(
                "select count(*) from loan_dw.dwd_loan_monthly_perf where release_id=:r and monthly_reporting_period=:m",
                r=RELEASE,
                m=datetime.fromisoformat(self.month),
            )
            if cur.fetchone()[0] == 0:
                self.skipTest(f"{RELEASE} has no rows for {self.month}")
            self.rule = p.select_rule(cur, self.month)
            cur.execute(
                "select count(*) from review_candidate where reporting_month=:m and rule_version_id=:r",
                m=datetime.fromisoformat(self.month),
                r=self.rule["rule_version_id"],
            )
            if cur.fetchone()[0]:
                self.skipTest(
                    f"candidates for {self.month} already exist; this test only cleans its own rows"
                )
        self.addCleanup(self.clean)

    def clean(self):
        with self.p.connection() as conn, conn.cursor() as cur:
            clean_candidates(
                cur,
                "reporting_month=:m and rule_version_id=:r",
                m=datetime.fromisoformat(self.month),
                r=self.rule["rule_version_id"],
            )
            cur.execute(
                "delete from review_candidate_delivery where json_value(manifest_json,'$.reporting_month')=:m",
                m=self.month,
            )
            conn.commit()

    def test_selection_matches_independent_count_and_repeats_cleanly(self):
        from datetime import date

        with self.p.connection() as conn, conn.cursor() as cur:
            cur.execute(
                """select loan_identifier, monthly_reporting_period, current_loan_delinquency_status
                from loan_dw.dwd_loan_monthly_perf where release_id=:r
                and monthly_reporting_period in (add_months(:m,-1), :m)""",
                r=RELEASE,
                m=datetime.fromisoformat(self.month),
            )
            status = {}
            for loan, period, code in cur.fetchall():
                status[(loan, period.date())] = self.p.level(code)
        report = date.fromisoformat(self.month)
        previous = date(
            report.year - (report.month == 1), (report.month - 2) % 12 + 1, 1
        )
        threshold = self.rule["min_delinquency_status"]
        expected = sorted(
            loan
            for (loan, period), lvl in status.items()
            if period == report
            and lvl is not None
            and lvl >= threshold
            and (status.get((loan, previous)) or 0) < threshold
        )
        self.assertGreater(len(expected), 0)
        delivery = self.p.publish(RELEASE, self.month)
        before = self.p.boundary()
        with self.p.connection() as conn, conn.cursor() as cur:
            cur.execute(
                """select c.loan_identifier, e.delivery_id from review_candidate c
                join review_evidence e on e.evidence_id=c.latest_evidence_id
                where c.reporting_month=:m and c.rule_version_id=:r and c.candidate_source='DW'
                order by c.loan_identifier""",
                m=datetime.fromisoformat(self.month),
                r=self.rule["rule_version_id"],
            )
            rows = cur.fetchall()
        self.assertEqual([r[0] for r in rows], expected)
        self.assertEqual({r[1].hex() for r in rows}, {delivery})
        self.assertEqual(self.p.publish(RELEASE, self.month), delivery)
        self.assertEqual(self.p.boundary(), before)


def setUpModule():
    """Before any fixture or failure cleanup in this module, verify the real database environment."""
    from db import connect_test_database

    connect_test_database().close()
