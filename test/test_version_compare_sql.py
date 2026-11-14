"""Static regression tests for the release comparison and targeted recomputation SQL.

Usage: .venv/bin/python test/test_version_compare_sql.py
Requires: nothing. Run directly or with python -m unittest.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class VersionCompareSqlTest(unittest.TestCase):
    def test_recompute_list_uses_exact_null_safe_comparison(self):
        sql = (ROOT / "source/dwd/find_recompute_loans.sql").read_text(encoding="utf-8")
        lower = sql.lower()
        self.assertNotIn("ora_hash", lower)
        self.assertIn("full outer join new_perf", lower)
        for column in (
            "origination_year",
            "origination_quarter",
            "first_payment_date",
            "monthly_reporting_period",
            "current_loan_delinquency_status",
            "zero_balance_code",
            "zero_balance_effective_date",
            "modification_flag",
            "data_source",
        ):
            with self.subTest(column=column):
                self.assertIn(column, lower)
        self.assertGreaterEqual(lower.count("decode("), 8)

    def test_compare_releases_rejects_empty_or_same_inputs(self):
        sql = (ROOT / "source/ads/compare_releases.sql").read_text(encoding="utf-8")
        self.assertIn("Base and new release must differ", sql)
        self.assertIn("Old release has incomplete DIM/DWD data", sql)
        self.assertIn("New release has incomplete DIM/DWD data", sql)

    def test_targeted_recompute_rejects_incomplete_inputs(self):
        sql = (ROOT / "source/dwd/recompute_downstream_targeted.sql").read_text(
            encoding="utf-8"
        )
        self.assertIn("New release has incomplete DIM/DWD data", sql)
        self.assertIn("Base release curve or transition results are absent", sql)


if __name__ == "__main__":
    unittest.main()
