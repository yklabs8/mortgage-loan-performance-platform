"""Candidate product contract; follows review_api.generate_candidates.

The three business files and the quality file reuse the delivery directory, row count, and SHA-256 contract; schema 2 is only for candidate import.
Analysis packages still use schema 1, and the analysis importer rejects candidate packages, so the wrong product cannot be written.
"""

import json
import re
import uuid
from datetime import date, datetime, timezone
from pathlib import Path

from delivery_contract import DQ_COLUMNS, digest, quality_status, read_file

KEY = ["rule_version_id", "data_source", "loan_identifier", "reporting_month"]
ORIGIN = [
    "classic_fico",
    "original_upb",
    "original_loan_to_value_ltv",
    "original_interest_rate",
    "property_state",
    "origination_year",
    "first_payment_date",
]
PERFORMANCE = [
    "current_loan_delinquency_status",
    "current_actual_upb",
    "current_interest_rate",
    "zero_balance_code",
    "zero_balance_effective_date",
    "modification_flag",
]
CANDIDATE_COLUMNS = {
    "review_candidate": KEY + ["delinquency_status", "source_release_id"],
    "review_evidence": KEY
    + ["source_release_id", "rule_code", "version_no", "min_delinquency_status"]
    + ORIGIN
    + PERFORMANCE
    + [
        "previous_delinquency_status",
        "previous_month_missing",
        "missing_months",
        "content_sha256",
    ],
    "review_evidence_month": KEY + ["monthly_reporting_period"] + PERFORMANCE,
}

# Fixed number format (8 decimals) in evidence files and content_sha256; the Oracle import recomputes digests with the same format
EVIDENCE_NUMBER_TYPE = "decimal(22,8)"
NUMERIC_COLUMNS = {
    "rule_version_id",
    "version_no",
    "min_delinquency_status",
    "classic_fico",
    "original_upb",
    "original_loan_to_value_ltv",
    "original_interest_rate",
    "origination_year",
    "current_actual_upb",
    "current_interest_rate",
}
DATE_COLUMNS = {
    "reporting_month",
    "first_payment_date",
    "zero_balance_effective_date",
    "monthly_reporting_period",
}


def file_metadata(table, columns):
    """Business keys and scalar types declared by the files, for the next Oracle import."""
    if table == "dq_check_result":
        return {
            "business_key": ["source_file_year", "rule_id"],
            "column_types": [
                "number"
                if c in {"checked_count", "bad_count", "source_file_year"}
                else "string"
                for c in columns
            ],
        }
    return {
        "business_key": KEY
        + (["monthly_reporting_period"] if table == "review_evidence_month" else []),
        "column_types": [
            "number"
            if c in NUMERIC_COLUMNS
            else "date"
            if c in DATE_COLUMNS
            else "boolean"
            if c == "previous_month_missing"
            else "string"
            for c in columns
        ],
    }


def validate_rule(rule, reporting_month):
    """Parameters must come from the version Oracle selected by effective date; the import checks them against the database again."""
    required = {
        "rule_code",
        "rule_version_id",
        "version_no",
        "min_delinquency_status",
        "effective_from",
    }
    if not isinstance(rule, dict) or set(rule) != required:
        raise ValueError("Incomplete rule parameters")
    if rule["rule_code"] != "DLQ60_ENTRY":
        raise ValueError("Only DLQ60_ENTRY is supported")
    for field in ("rule_version_id", "version_no", "min_delinquency_status"):
        if type(rule[field]) is not int or rule[field] <= 0:
            raise ValueError(f"Invalid rule {field}")
    month = date.fromisoformat(reporting_month)
    effective = date.fromisoformat(rule["effective_from"])
    if (
        month.day != 1
        or month.isoformat() != reporting_month
        or effective.isoformat() != rule["effective_from"]
        or effective > month
    ):
        raise ValueError("Rule not yet effective or reporting month not the first day")


def build_candidate_manifest(
    folder,
    dataset,
    release,
    years,
    commit,
    dirty,
    rule,
    reporting_month,
    generation,
    metric_sha256,
    delivery_id=None,
):
    validate_rule(rule, reporting_month)
    folder = Path(folder)
    files = []
    for table, columns in {**CANDIDATE_COLUMNS, "dq_check_result": DQ_COLUMNS}.items():
        paths = (
            [folder / "dq_check_result.csv"]
            if table == "dq_check_result"
            else list((folder / table).glob("part-*.csv"))
        )
        if len(paths) != 1:
            raise ValueError(f"{table} must have exactly one CSV")
        p = paths[0]
        files.append(
            {
                "table": table,
                "path": str(p.relative_to(folder)),
                "columns": columns,
                "rows": sum(1 for _ in read_file(p, columns)),
                "sha256": digest(p),
                **file_metadata(table, columns),
            }
        )
    manifest = {
        "schema_version": 2,
        "product": "REVIEW_CANDIDATES",
        "delivery_id": delivery_id or uuid.uuid4().hex,
        "dataset": dataset,
        "release": release,
        "source_years": sorted(set(map(int, years))),
        "code_commit": commit,
        "workspace_dirty": dirty,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "reporting_month": reporting_month,
        "input_cutoff": reporting_month,
        "input_generation": generation,
        "metric_sha256": metric_sha256,
        "rule": rule,
        "quality_status": quality_status(folder, years),
        "files": files,
    }
    (folder / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    )
    validate_candidate_package(folder)
    return manifest


def validate_candidate_package(folder):
    folder = Path(folder).resolve()
    m = json.loads((folder / "manifest.json").read_text())
    if m.get("schema_version") != 2 or m.get("product") != "REVIEW_CANDIDATES":
        raise ValueError("Unknown candidate structure or product")
    validate_rule(m.get("rule"), m["reporting_month"])
    for field, size in [
        ("delivery_id", 32),
        ("input_generation", 32),
        ("metric_sha256", 64),
        ("code_commit", 40),
    ]:
        if not re.fullmatch(f"[0-9a-f]{{{size}}}", m.get(field) or ""):
            raise ValueError(f"Invalid {field}")
    years = m["source_years"]
    if (
        m["dataset"] not in {"full", "sample"}
        or not re.fullmatch(r"R[0-9]+", m["release"])
        or not years
        or years != sorted(set(years))
        or any(type(y) is not int or not 1999 <= y <= 9999 for y in years)
        or type(m["workspace_dirty"]) is not bool
        or m["input_cutoff"] != m["reporting_month"]
    ):
        raise ValueError("Invalid candidate scope")
    definitions = {**CANDIDATE_COLUMNS, "dq_check_result": DQ_COLUMNS}
    if len(m["files"]) != len(definitions) or {i["table"] for i in m["files"]} != set(
        definitions
    ):
        raise ValueError("Candidate files incomplete or duplicated")
    counts = {}
    for item in m["files"]:
        p = (folder / item["path"]).resolve()
        if (
            not p.is_relative_to(folder)
            or item["columns"] != definitions[item["table"]]
            or any(
                item.get(k) != v
                for k, v in file_metadata(item["table"], item["columns"]).items()
            )
            or digest(p) != item["sha256"]
            or type(item["rows"]) is not int
            or sum(1 for _ in read_file(p, item["columns"])) != item["rows"]
        ):
            raise ValueError("Candidate file path, column names, digest, or row count mismatch")
        counts[item["table"]] = item["rows"]
    if counts["review_candidate"] != counts["review_evidence"] or not (
        counts["review_candidate"]
        <= counts["review_evidence_month"]
        <= 13 * counts["review_candidate"]
    ):
        raise ValueError("Candidate and evidence row counts differ")
    actual = quality_status(folder, years)
    if actual == "FAIL" or actual != m["quality_status"]:
        raise ValueError("Candidate quality check failed")
    return m
