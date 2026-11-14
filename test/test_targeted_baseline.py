"""Targeted recomputation: matches the full result, handles a release with no transitions, and checks the baseline modification summary before changing target data."""

import hashlib
import sys
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from db import connect_test_database as connect


class TargetedBaselineTest(unittest.TestCase):
    def test_targeted_results_match_existing_full_result(self):
        tables = {
            "dws_perf_loan_td": "loan_identifier",
            "dws_mod_loan_td": "loan_identifier",
            "ads_vintage_dlq60_curve": (
                "origination_year, origination_quarter, months_on_book"
            ),
            "ads_dlq_transition_monthly": (
                "origination_year, monthly_reporting_period, from_state, to_state"
            ),
            "ads_modification_outcome": (
                "origination_year, first_mod_year, before_mod_group"
            ),
        }

        def fingerprint(cur, table, order):
            cur.execute(
                "select lower(column_name) from user_tab_columns "
                "where table_name = :table_name order by column_id",
                table_name=table.upper(),
            )
            columns = [row[0] for row in cur.fetchall()]
            self.assertTrue(columns)
            cur.execute(
                f"select {', '.join(columns)} from {table} "
                f"where release_id = :release_id order by {order}",
                release_id="R46",
            )
            digest = hashlib.sha256()
            rows = 0
            for row in cur:
                digest.update(repr(tuple(str(value) for value in row)).encode())
                digest.update(b"\n")
                rows += 1
            return rows, digest.hexdigest()

        with connect() as conn, conn.cursor() as cur:
            try:
                before = {
                    table: fingerprint(cur, table, order)
                    for table, order in tables.items()
                }
                cur.callproc("recompute_downstream_targeted", ["R45", "R46"])
                after = {
                    table: fingerprint(cur, table, order)
                    for table, order in tables.items()
                }
                self.assertEqual(before, after)
            finally:
                conn.rollback()

    def test_zero_transition_release_completes(self):
        token = uuid.uuid4().hex[:7].upper()
        base = "ZB" + token
        target = "ZT" + token

        def clone(cur, table, source_where, changes, excluded=()):
            cur.execute(f"select * from {table} where {source_where}")
            row = cur.fetchone()
            self.assertIsNotNone(row)
            names = [item[0].lower() for item in cur.description]
            values = dict(zip(names, row, strict=True))
            values.update(changes)
            # Virtual columns are computed by the database; a SELECT * row cannot be inserted back as-is.
            cur.execute(
                "select lower(column_name) from user_tab_cols "
                "where table_name = :table_name and virtual_column = 'YES'",
                table_name=table.upper(),
            )
            for (name,) in cur:
                values.pop(name, None)
            for name in excluded:
                values.pop(name)
            columns = ", ".join(values)
            binds = ", ".join(f":{name}" for name in values)
            cur.execute(f"insert into {table} ({columns}) values ({binds})", values)

        with connect() as conn, conn.cursor() as cur:
            try:
                cur.execute(
                    "select p.loan_identifier, p.monthly_reporting_period "
                    "from dwd_loan_monthly_perf p join dim_loan l "
                    "on l.release_id = p.release_id "
                    "and l.loan_identifier = p.loan_identifier "
                    "where p.release_id = 'R45' and p.modification_flag is null "
                    "and p.monthly_reporting_period >= l.first_payment_date "
                    "fetch first 1 row only"
                )
                loan, period = cur.fetchone()
                source_dim = "release_id = 'R45' and loan_identifier = '" + loan + "'"
                source_perf = (
                    "release_id = 'R45' and loan_identifier = '"
                    + loan
                    + "' and monthly_reporting_period = date '"
                    + period.strftime("%Y-%m-%d")
                    + "'"
                )
                for release in (base, target):
                    clone(
                        cur,
                        "dim_loan",
                        source_dim,
                        {"release_id": release},
                        excluded=("loan_key",),
                    )
                    cur.execute(
                        "select loan_key from dim_loan "
                        "where release_id = :release and loan_identifier = :loan",
                        release=release,
                        loan=loan,
                    )
                    new_key = cur.fetchone()[0]
                    clone(
                        cur,
                        "dwd_loan_monthly_perf",
                        source_perf,
                        {"release_id": release, "loan_key": new_key},
                    )
                cur.callproc("load_dws_perf_loan_td", [base])
                cur.callproc("load_dws_mod_loan_td", [base])
                cur.callproc("load_ads_vintage_dlq60_curve", [base])
                cur.callproc("load_ads_dlq_transition_monthly", [base])
                cur.execute(
                    "select count(*) from ads_dlq_transition_monthly "
                    "where release_id = :release",
                    release=base,
                )
                self.assertEqual(cur.fetchone()[0], 0)
                cur.callproc("recompute_downstream_targeted", [base, target])
                cur.execute(
                    "select count(*) from ads_dlq_transition_monthly "
                    "where release_id = :release",
                    release=target,
                )
                self.assertEqual(cur.fetchone()[0], 0)
            finally:
                conn.rollback()

    def test_missing_unchanged_mod_loan_is_rejected(self):
        with connect() as conn, conn.cursor() as cur:
            try:
                cur.callproc("find_recompute_loans", ["R45", "R46"])
                cur.execute(
                    "select min(m.loan_identifier) from dws_mod_loan_td m "
                    "where m.release_id = 'R45' and not exists ("
                    "select 1 from dw_recompute_loan r "
                    "where r.release_id = 'R46' "
                    "and r.loan_identifier = m.loan_identifier)"
                )
                loan = cur.fetchone()[0]
                self.assertIsNotNone(loan)
                cur.execute(
                    "delete from dws_mod_loan_td "
                    "where release_id = 'R45' and loan_identifier = :loan",
                    loan=loan,
                )
                with self.assertRaisesRegex(Exception, "Base release modification summary"):
                    cur.callproc("recompute_downstream_targeted", ["R45", "R46"])
            finally:
                conn.rollback()


if __name__ == "__main__":
    unittest.main()


def setUpModule():
    """Check the database environment marker before any fixture or cleanup in this module."""
    from db import connect_test_database

    connect_test_database().close()
