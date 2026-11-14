"""Delivery file contract; column order comes from source/ads/ads_*.sql and quality rules from checks/dq_*.sql."""

import csv
import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

TABLE_COLUMNS = {
    "ads_vintage_dlq60_curve": [
        "origination_year",
        "origination_quarter",
        "months_on_book",
        "cohort_loans",
        "eligible_loans",
        "cum_dlq60_loans",
        "cum_dlq60_rate",
    ],
    "ads_dlq_transition_monthly": [
        "origination_year",
        "monthly_reporting_period",
        "from_state",
        "from_state_order",
        "to_state",
        "to_state_order",
        "loan_count",
    ],
    "ads_modification_outcome": [
        "origination_year",
        "first_mod_year",
        "before_mod_group",
        "modified_loans",
        "observable_12m_loans",
        "redefault_12m_loans",
        "current_12m_loans",
        "prepaid_12m_loans",
        "redefault_12m_rate",
        "current_12m_rate",
    ],
    "ads_dlq_transition_segment": [
        "origination_year",
        "monthly_reporting_period",
        "from_state",
        "from_state_order",
        "to_state",
        "to_state_order",
        "segment_type",
        "segment_value",
        "loan_count",
    ],
    "ads_final_outcome_segment": [
        "origination_year",
        "segment_type",
        "segment_value",
        "final_state",
        "loan_count",
    ],
    "ads_cure_redefault_segment": [
        "origination_year",
        "segment_type",
        "segment_value",
        "dlq60_loans",
        "cured_loans",
        "cure_events",
        "redefault_loans",
        "cure_rate",
    ],
    "ads_vintage_dlq60_segment": [
        "origination_year",
        "origination_quarter",
        "months_on_book",
        "segment_type",
        "segment_value",
        "cohort_loans",
        "eligible_loans",
        "cum_dlq60_loans",
        "cum_dlq60_rate",
    ],
    "ads_modification_segment": [
        "origination_year",
        "first_mod_year",
        "before_mod_group",
        "segment_type",
        "segment_value",
        "modified_loans",
        "observable_12m_loans",
        "redefault_12m_loans",
        "current_12m_loans",
        "prepaid_12m_loans",
        "redefault_12m_rate",
        "current_12m_rate",
    ],
}
DQ_COLUMNS = [
    "rule_id",
    "dw_layer",
    "severity",
    "checked_count",
    "bad_count",
    "status",
    "checked_at",
    "source_file_year",
]
REQUIRED_RULES = {
    "DQ000",
    "DQ003",
    "DQ004",
    "DQ004B",
    "DQ005",
    "DQ006",
    "DQ007A",
    "DQ007B",
    "DQ008",
    "DQ009",
    "DQ013",
    "DQ014A",
    "DQ014B",
}


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_file(path, columns):
    with Path(path).open(encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        if next(reader, None) != columns:
            raise ValueError(f"{path} column names mismatch")
        for line, row in enumerate(reader, 2):
            if len(row) != len(columns):
                raise ValueError(f"{path}:{line} column count mismatch")
            yield row


def quality_status(folder, years):
    found = {}
    overall = "PASS"
    for row in read_file(Path(folder) / "dq_check_result.csv", DQ_COLUMNS):
        item = dict(zip(DQ_COLUMNS, row))
        key = (int(item["source_file_year"]), item["rule_id"])
        if key in found or key[0] not in years:
            raise ValueError("Duplicate or out-of-range quality rule source years")
        found[key] = item
        bad = int(item["bad_count"])
        checked = int(item["checked_count"])
        if bad < 0 or checked < 0 or item["status"] not in {"PASS", "WARN", "FAIL"}:
            raise ValueError("Invalid quality rule status or count")
        warn = item["rule_id"] in {"DQ004B", "DQ007B", "DQ008", "DQ009"}
        quarantine = item["rule_id"] in {"DQ004", "DQ006"}
        expected = "PASS" if bad == 0 else ("WARN" if warn or quarantine else "FAIL")
        if expected != item["status"] or item["severity"] != (
            "WARN" if warn else "HARD"
        ):
            raise ValueError("Quality rule severity, count, and status disagree")
        if expected == "FAIL":
            overall = "FAIL"
        elif expected == "WARN" and overall != "FAIL":
            overall = "WARN"
    for year in years:
        if not REQUIRED_RULES.issubset({r for y, r in found if y == year}):
            raise ValueError(f"{year} is missing required quality rules")
    return overall


def build_manifest(
    folder,
    dataset,
    release,
    years,
    commit,
    dirty,
    delivery_id=None,
    calculations=None,
    input_cutoff=None,
    input_generation=None,
    metric_sha256=None,
):
    folder = Path(folder)
    files = []
    for table, columns in {**TABLE_COLUMNS, "dq_check_result": DQ_COLUMNS}.items():
        paths = (
            [folder / "dq_check_result.csv"]
            if table == "dq_check_result"
            else list((folder / table).glob("part-*.csv"))
        )
        if len(paths) != 1:
            raise ValueError(f"{table} must have exactly one CSV")
        p = paths[0]
        rows = sum(1 for _ in read_file(p, columns))
        files.append(
            {
                "table": table,
                "path": str(p.relative_to(folder)),
                "columns": columns,
                "rows": rows,
                "sha256": digest(p),
            }
        )
    manifest = {
        "schema_version": 1,
        "delivery_id": delivery_id or uuid.uuid4().hex,
        "dataset": dataset,
        "release": release,
        "source_years": sorted(set(map(int, years))),
        "code_commit": commit,
        "workspace_dirty": dirty,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "quality_status": quality_status(folder, years),
        "files": files,
        "calculations": calculations or [],
        "input_cutoff": input_cutoff,
        "input_generation": input_generation,
        "metric_sha256": metric_sha256,
    }
    (folder / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    )
    return manifest


def validate_package(folder):
    folder = Path(folder).resolve()
    m = json.loads((folder / "manifest.json").read_text())
    if m["schema_version"] != 1:
        raise ValueError("Unknown schema_version")
    if not re.fullmatch("[0-9a-f]{32}", m.get("input_generation") or ""):
        raise ValueError("Missing valid input and analysis completion generation")
    if not re.fullmatch("[0-9a-f]{64}", m.get("metric_sha256") or ""):
        raise ValueError("Missing metric file digest")
    if not re.fullmatch("[0-9a-f]{32}", m["delivery_id"]):
        raise ValueError("Invalid delivery_id")
    if m["dataset"] not in {"sample", "full"} or not re.fullmatch(
        "R[0-9]+", m["release"]
    ):
        raise ValueError("Invalid data scope")
    years = m["source_years"]
    if (
        not years
        or years != sorted(set(years))
        or any(type(y) is not int or y < 1999 or y > 9999 for y in years)
    ):
        raise ValueError("Invalid source year")
    if not isinstance(m["workspace_dirty"], bool) or not re.fullmatch(
        "[0-9a-f]{40}", m["code_commit"]
    ):
        raise ValueError("Missing code commit / workspace state")
    definitions = {**TABLE_COLUMNS, "dq_check_result": DQ_COLUMNS}
    if len(m["files"]) != len(definitions) or {i["table"] for i in m["files"]} != set(
        definitions
    ):
        raise ValueError("Files incomplete or duplicated")
    for item in m["files"]:
        p = (folder / item["path"]).resolve()
        if not p.is_relative_to(folder):
            raise ValueError("File path outside the delivery directory")
        if digest(p) != item["sha256"]:
            raise ValueError(f"{item['table']} SHA-256 mismatch")
        if item["columns"] != definitions[item["table"]]:
            raise ValueError("Manifest column names mismatch")
        if sum(1 for _ in read_file(p, item["columns"])) != item["rows"]:
            raise ValueError("Manifest row count mismatch")
    actual = quality_status(folder, years)
    if m["quality_status"] == "FAIL" or actual == "FAIL":
        raise ValueError("Quality FAIL; publication refused")
    if actual != m["quality_status"]:
        raise ValueError("Quality summary status mismatch")
    return m
