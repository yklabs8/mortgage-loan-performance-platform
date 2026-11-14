"""Counterexamples for the candidate delivery contract: zero rows, metadata, and rejection of corrupted packages."""

import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "spark"))


class CandidateContractTest(unittest.TestCase):
    def test_zero_and_rule_metadata(self):
        import candidate_contract as c
        from delivery_contract import DQ_COLUMNS, REQUIRED_RULES

        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            for table, columns in c.CANDIDATE_COLUMNS.items():
                (folder / table).mkdir()
                with (folder / table / "part-000.csv").open("w") as f:
                    csv.writer(f).writerow(columns)
            with (folder / "dq_check_result.csv").open("w") as f:
                w = csv.writer(f)
                w.writerow(DQ_COLUMNS)
                for rule in REQUIRED_RULES:
                    w.writerow(
                        [
                            rule,
                            "ODS",
                            "WARN"
                            if rule in {"DQ004B", "DQ007B", "DQ008", "DQ009"}
                            else "HARD",
                            1,
                            0,
                            "PASS",
                            "2026-10-19T00:00:00Z",
                            2010,
                        ]
                    )
            rule = {
                "rule_code": "DLQ60_ENTRY",
                "rule_version_id": 1,
                "version_no": 1,
                "min_delinquency_status": 2,
                "effective_from": "2020-01-01",
            }
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
            self.assertEqual(c.validate_candidate_package(folder), m)
            self.assertEqual([i["rows"] for i in m["files"][:3]], [0, 0, 0])
            self.assertEqual(m["rule"], rule)
            # Each corrupted manifest is mutated independently from the valid original and does not affect other assertions.
            original = json.dumps(m)
            for field, value in [
                ("schema_version", 99),
                ("product", "LOAN_ANALYSIS"),
                ("input_generation", None),
                ("source_years", []),
                ("reporting_month", "2020-06-02"),
            ]:
                broken = json.loads(original)
                broken[field] = value
                (folder / "manifest.json").write_text(json.dumps(broken))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    c.validate_candidate_package(folder)
            for field, value in [
                ("sha256", "0" * 64),
                ("rows", 1),
                ("columns", ["unexpected"]),
                ("path", "../outside.csv"),
            ]:
                broken = json.loads(original)
                broken["files"][0][field] = value
                (folder / "manifest.json").write_text(json.dumps(broken))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    c.validate_candidate_package(folder)
            broken = json.loads(original)
            broken["rule"]["min_delinquency_status"] = None
            (folder / "manifest.json").write_text(json.dumps(broken))
            with self.assertRaises(ValueError):
                c.validate_candidate_package(folder)

    def test_rule_validation(self):
        import candidate_contract as c

        for rule in [
            {},
            {
                "rule_code": "DLQ60_ENTRY",
                "rule_version_id": 1,
                "version_no": 1,
                "min_delinquency_status": 2,
                "effective_from": "2020-07-01",
            },
        ]:
            with self.assertRaises(ValueError):
                c.validate_rule(rule, "2020-06-01")
