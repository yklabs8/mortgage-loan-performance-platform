"""Independently reconcile roll-rate counts from raw monthly files.

Usage: python python/reconcile_transition.py RELEASE PERF PERF_HEADER
Definitions: docs/metric_definitions.md section 5. States are recomputed without reading dimensions.
New layout only (R47 onward). Every cell must match. Requires python/db.py and populated ADS.
"""

import csv  
import sys  
from collections import Counter, defaultdict  
from itertools import pairwise  

from db import connect  

EXIT = {  
    "01": "PREPAID",
    "02": "LIQUIDATED",
    "03": "LIQUIDATED",
    "09": "LIQUIDATED",
    "15": "LOAN_SALE",
    "16": "LOAN_SALE",
    "96": "DEFECT",
}


def months(yyyymm):  
    return int(yyyymm[:4]) * 12 + int(yyyymm[4:6])


def state(status, zbc):  
    if zbc:  
        return EXIT[zbc]
    if status == "RA":  
        return "REO"
    if not status.isdigit():  
        return "UNK"
    return ["C", "30", "60", "90"][int(status)] if int(status) < 4 else "120+"


def main(release_id, perf, perf_hdr):
    with open(perf_hdr, encoding="utf-8") as f:  
        header = f.readline().rstrip("\r\n").split("|")
    i_loan = header.index("LOAN IDENTIFIER")  
    i_period = header.index("PERIOD")
    i_status = header.index("CURRENT LOAN DELINQUENCY STATUS")
    i_zbc = header.index("ZERO BALANCE CODE")
    rows = defaultdict(list)  
    with open(perf, encoding="utf-8", newline="") as f:
        for line_no, r in enumerate(
            csv.reader(f, delimiter="|", quoting=csv.QUOTE_NONE), start=1
        ):
            if len(r) != len(header):
                raise ValueError(f"Line {line_no} has {len(r)} columns; header requires {len(header)} columns")
            rows[r[i_loan]].append((r[i_period], state(r[i_status], r[i_zbc])))
    if not rows:
        raise ValueError(f"{perf} is empty")
    expected = Counter()  
    for loan, recs in rows.items():
        yy = loan[1:3]  
        year = 1999 if yy == "99" else 2000 + int(yy)
        recs.sort()  
        for (p0, s0), (p1, s1) in pairwise(recs):  
            if months(p1) - months(p0) == 1:  
                expected[(year, p1, s0, s1)] += 1
    
    
    years = {1999 if loan[1:3] == "99" else 2000 + int(loan[1:3]) for loan in rows}
    with connect() as conn, conn.cursor() as cur:  
        cur.execute(
            "select origination_year, to_char(monthly_reporting_period, 'YYYYMM'),"
            " from_state, to_state, loan_count"
            " from ads_dlq_transition_monthly where release_id = :r",
            r=release_id,
        )
        
        db = {(y, p, a, b): n for y, p, a, b, n in cur if y in years}
    bad = [(k, expected.get(k), db.get(k)) for k in expected.keys() | db.keys()]
    bad = [b for b in bad if b[1] != b[2]]  
    if bad:
        for k, e, d in sorted(bad)[:5]:
            print(f"Mismatch {k}: Python {e}, database {d}", file=sys.stderr)
        raise RuntimeError(f"{len(bad)} cells differ")
    total = sum(expected.values())
    print(
        f"{release_id} {sorted(years)}: {len(expected)} cells, {total} transitions all match"
    )


if __name__ == "__main__":  
    if len(sys.argv) != 4:  
        sys.exit(__doc__)  
    main(*sys.argv[1:])
