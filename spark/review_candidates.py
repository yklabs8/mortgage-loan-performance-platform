"""Spark candidate and evidence computation; no Oracle connection. Follows review_api.generate_candidates.

The caller supplies dim/dwd for one release and source scope, plus the pre-exported rule version.
Monthly evidence contains only months that actually exist; missing months are listed explicitly in missing_months.
"""

from pyspark.sql import functions as F

from candidate_contract import (
    CANDIDATE_COLUMNS,
    EVIDENCE_NUMBER_TYPE,
    KEY,
    NUMERIC_COLUMNS,
    ORIGIN,
    PERFORMANCE,
    validate_rule,
)


def dlq_level(column):
    # Follows review_api.dlq_level; RA = 99 (User Guide p.10), any other non-numeric value is null.
    return F.when(column == "RA", F.lit(99)).when(
        column.rlike("^[0-9]+$"), column.cast("decimal(38,0)")
    )


def build_candidates(dim, perf, reporting_month, rule, release):
    validate_rule(rule, reporting_month)
    identity = ["data_source", "loan_identifier"]
    # DWD and DIM both have origination-year / partition columns; bring in only the performance columns the evidence needs, avoiding name clashes and misuse of the source year.
    perf = perf.select(*identity, "monthly_reporting_period", *PERFORMANCE)
    # Detail is stored with official precision; evidence output and digests are fixed to EVIDENCE_NUMBER_TYPE by contract, so stored digests stay comparable.
    dim, perf = (
        frame.select(
            *[
                F.col(c).cast(EVIDENCE_NUMBER_TYPE).alias(c)
                if c in NUMERIC_COLUMNS and c != "origination_year"
                else F.col(c)
                for c in frame.columns
            ]
        )
        for frame in (dim, perf)
    )
    report = F.to_date(F.lit(reporting_month))
    current = perf.where(F.col("monthly_reporting_period") == report)
    previous = perf.where(
        F.col("monthly_reporting_period") == F.add_months(report, -1)
    ).select(
        *identity,
        F.col("current_loan_delinquency_status").alias("previous_delinquency_status"),
        F.lit(False).alias("previous_month_missing"),
    )
    selected = current.join(previous, identity, "left").where(
        (
            dlq_level(F.col("current_loan_delinquency_status"))
            >= rule["min_delinquency_status"]
        )
        & (
            F.coalesce(dlq_level(F.col("previous_delinquency_status")), F.lit(0))
            < rule["min_delinquency_status"]
        )
    )
    selected = (
        selected.withColumn(
            "previous_month_missing", F.coalesce("previous_month_missing", F.lit(True))
        )
        .withColumn("rule_version_id", F.lit(rule["rule_version_id"]))
        .withColumn("reporting_month", report)
        .withColumn("source_release_id", F.lit(release))
    )
    candidates = selected.withColumn(
        "delinquency_status", F.col("current_loan_delinquency_status")
    ).select(*CANDIDATE_COLUMNS["review_candidate"])
    monthly = (
        perf.where(
            F.col("monthly_reporting_period").between(F.add_months(report, -12), report)
        )
        .join(candidates.select(*KEY), identity, "inner")
        .select(*CANDIDATE_COLUMNS["review_evidence_month"])
    )
    # JSON with fixed column order; numbers come from DWD decimals, keeping NULL distinct from a missing month; the digest covers 13 months of content.
    payload = monthly.groupBy(*KEY).agg(
        F.sort_array(
            F.collect_list(F.struct("monthly_reporting_period", *PERFORMANCE))
        ).alias("months")
    )
    evidence = selected.join(dim.select(*identity, *ORIGIN), identity, "inner").join(
        payload, KEY, "inner"
    )
    for field in ("rule_code", "version_no", "min_delinquency_status"):
        evidence = evidence.withColumn(field, F.lit(rule[field]))
    evidence = evidence.withColumn(
        "missing_months",
        F.concat_ws(
            "|",
            F.transform(
                F.array_except(
                    F.sequence(
                        F.add_months(report, -12), report, F.expr("interval 1 month")
                    ),
                    F.transform("months", lambda x: x.monthly_reporting_period),
                ),
                lambda x: F.date_format(x, "yyyy-MM-dd"),
            ),
        ),
    )
    columns = [c for c in CANDIDATE_COLUMNS["review_evidence"] if c != "content_sha256"]
    evidence = evidence.withColumn(
        "content_sha256",
        F.sha2(
            F.to_json(F.struct(*columns, "months"), {"ignoreNullFields": "false"}), 256
        ),
    ).select(*CANDIDATE_COLUMNS["review_evidence"])
    return {
        "review_candidate": candidates,
        "review_evidence": evidence,
        "review_evidence_month": monthly,
    }
