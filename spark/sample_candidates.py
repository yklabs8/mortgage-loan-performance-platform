"""Sample candidates: Spark local mode reads files exported from the Oracle sample warehouse and builds a candidate delivery package in the production format.

Usage: LOAN_CODE_COMMIT=<40-char commit> LOAN_CODE_DIRTY=0|1 LOAN_METRIC_SHA256=<SHA-256 of the metric file> \\
      spark-submit --master local[2] \\
        --py-files candidate_contract.py,delivery_contract.py,review_candidates.py \\
        sample_candidates.py <input dir> <output dir> <release> <YYYY-MM-01> <source year>
Input dir: dim_loan.csv, dwd_loan_monthly_perf.csv, dq_check_result.csv exported by python/export_dims_for_spark.py <dir> <release> <source year>,
plus the output of python/export_candidate_rule.py saved as rule.json.
Output: <output dir>/deliveries/<delivery_id>/, imported as is by python/candidate_import.py;
LOAN_CANDIDATE_DELIVERY_ID may set the delivery ID (as in production).
No HDFS, Hive, or Oracle connection; selection logic lives only in review_candidates.build_candidates, and the manifest is produced only by
candidate_contract.build_candidate_manifest. Called by: the deployment steps in README, test/test_sample_candidates.py.
"""

import hashlib
import json
import os
import re
import shutil
import sys
import uuid
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

import freddie_layout as layout
from candidate_contract import (
    DATE_COLUMNS,
    NUMERIC_COLUMNS,
    ORIGIN,
    PERFORMANCE,
    build_candidate_manifest,
    validate_rule,
)
from delivery_contract import digest
from review_candidates import build_candidates

IDENTITY = ["data_source", "loan_identifier"]
INPUTS = {  # file -> column order, matching the export of export_dims_for_spark.py
    "dim_loan.csv": IDENTITY + ORIGIN,
    "dwd_loan_monthly_perf.csv": IDENTITY + ["monthly_reporting_period"] + PERFORMANCE,
}


def read_input(spark, path, columns):
    """Read everything as text, then convert strictly to the production table types; fail on mismatched column names or failed conversions."""
    frame = spark.read.option("header", True).csv(f"file://{path}")
    if frame.columns != columns:
        raise ValueError(f"{path.name} column names mismatch: {frame.columns}")
    for c in columns:
        if c == "origination_year":
            frame = frame.withColumn(c, F.col(c).cast("int"))
        elif c in NUMERIC_COLUMNS:
            # Same official precision as the production detail (freddie_layout.NUMERIC_TYPES)
            frame = frame.withColumn(c, F.col(c).cast(layout.decimal_type(c)))
        elif c in DATE_COLUMNS:
            frame = frame.withColumn(c, F.to_date(c, "yyyy-MM-dd"))
    return frame


def main(in_dir, out_dir, release, reporting_month, year):
    in_dir, out_dir = Path(in_dir).resolve(), Path(out_dir).resolve()
    rule = json.loads((in_dir / "rule.json").read_text())
    validate_rule(rule, reporting_month)
    if not re.fullmatch(r"R[0-9]+", release):
        raise ValueError("Invalid release")
    delivery_id = os.environ.get("LOAN_CANDIDATE_DELIVERY_ID") or uuid.uuid4().hex
    if not re.fullmatch("[0-9a-f]{32}", delivery_id):
        raise ValueError("Invalid candidate delivery ID")
    # Production records the DWD completion generation; the sample records a digest of the three input files, so the generation changes when inputs change.
    inputs = "".join(digest(in_dir / n) for n in [*INPUTS, "dq_check_result.csv"])
    generation = hashlib.sha256(inputs.encode()).hexdigest()[:32]
    spark = (
        SparkSession.builder.master("local[2]")
        .appName(f"sample_candidates {release} {reporting_month}")
        .config("spark.sql.ansi.enabled", "true")  # fail on any type conversion that does not fit
        .config("spark.sql.session.timeZone", "UTC")
        .config("spark.sql.shuffle.partitions", "2")
        .getOrCreate()
    )
    try:
        dim, perf = (read_input(spark, in_dir / n, c) for n, c in INPUTS.items())
        frames = build_candidates(dim, perf, reporting_month, rule, release)
        target = out_dir / "deliveries" / delivery_id
        for name, df in frames.items():
            df.coalesce(1).write.mode("error").option("header", True).csv(
                f"file://{target / name}"
            )
    finally:
        spark.stop()
    shutil.copyfile(in_dir / "dq_check_result.csv", target / "dq_check_result.csv")
    build_candidate_manifest(
        target,
        "sample",
        release,
        [int(year)],
        os.environ["LOAN_CODE_COMMIT"],
        os.environ["LOAN_CODE_DIRTY"] == "1",
        rule,
        reporting_month,
        generation,
        os.environ["LOAN_METRIC_SHA256"],
        delivery_id,
    )
    print(f"DELIVERY_PATH={target}", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
