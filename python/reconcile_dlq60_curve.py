"""Independently reconcile the cumulative 60+ curve from raw new-layout text files.

Usage: python python/reconcile_dlq60_curve.py RELEASE ORIG ORIG_HEADER PERF PERF_HEADER
Every origination-quarter/month must match the Oracle ADS result.
"""
import csv
import sys
from collections import Counter

from db import connect


def read(data_path, header_path):
    with open(header_path, encoding="utf-8") as f:
        header = f.readline().rstrip("\r\n").split("|")
    with open(data_path, encoding="utf-8", newline="") as f:
        for line_no, row in enumerate(
            csv.reader(f, delimiter="|", quoting=csv.QUOTE_NONE), start=1
        ):
            if len(row) != len(header):
                raise ValueError(
                    f"row {line_no} has {len(row)} columns; header requires {len(header)}"
                )
            yield dict(zip(header, row))


def months(yyyymm):
    return int(yyyymm[:4]) * 12 + int(yyyymm[4:6])


def is_dlq60(status):
    return status == "RA" or (status.isdigit() and int(status) >= 2)


def main(release_id, orig, orig_hdr, perf, perf_hdr):
    first_pay, vintage = {}, {}
    for r in read(orig, orig_hdr):
        loan = r["LOAN IDENTIFIER"]
        first_pay[loan] = months(r["FIRST PAYMENT DATE"])
        yy = loan[1:3]
        vintage[loan] = (1999 if yy == "99" else 2000 + int(yy), int(loan[4]))
    if not first_pay:
        raise ValueError(f"{orig} is empty")
    first_hit, cutoff = {}, 0
    for r in read(perf, perf_hdr):
        loan = r["LOAN IDENTIFIER"]
        cutoff = max(cutoff, months(r["PERIOD"]))
        if is_dlq60(r["CURRENT LOAN DELINQUENCY STATUS"]):
            mob = months(r["PERIOD"]) - first_pay[loan] + 1
            first_hit[loan] = min(first_hit.get(loan, mob), mob)
    if cutoff == 0:
        raise ValueError(f"{perf} is empty")

    max_mob = {k: cutoff - v + 1 for k, v in first_pay.items()}
    cohort = Counter(vintage.values())
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "select origination_year, origination_quarter, months_on_book,"
            " eligible_loans, cum_dlq60_loans"
            " from ads_vintage_dlq60_curve where release_id = :r",
            r=release_id,
        )

        db = {((y, q), m): (c, n) for y, q, m, c, n in cur if (y, q) in cohort}
    expected = {}
    for v in cohort:
        loans = [k for k in vintage if vintage[k] == v]
        for m in range(1, max(max_mob[k] for k in loans) + 1):
            able = [k for k in loans if max_mob[k] >= m]
            hit = sum(1 for k in able if first_hit.get(k, m + 1) <= m)
            expected[(v, m)] = (len(able), hit)
    bad = [(k, expected.get(k), db.get(k)) for k in expected.keys() | db.keys()]
    bad = [b for b in bad if b[1] != b[2]]
    if bad:
        for k, e, d in sorted(bad)[:5]:
            print(f"mismatch {k}: Python {e}, database {d}", file=sys.stderr)
        raise RuntimeError(f"{len(bad)} months do not match")
    print(f"{release_id}: all {len(expected)} quarter/month pairs match")
    by_year = Counter()
    for ((y, _), m), (c, n) in expected.items():
        by_year[(y, m, "c")] += c
        by_year[(y, m, "n")] += n
    for y, m in sorted({(k[0], k[1]) for k in by_year}):
        if m in (12, 24, 60):
            c, n = by_year[(y, m, "c")], by_year[(y, m, "n")]
            print(f"  {y} origination, month {m}: {n} / {c} = {n / c:.4%}")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
