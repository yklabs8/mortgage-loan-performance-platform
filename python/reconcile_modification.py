"""Independently reconcile modified loans from raw monthly files.

Usage: python python/reconcile_modification.py RELEASE PERF PERF_HEADER
Definitions: docs/metric_definitions.md section 6. No dimension lookup. New layout only.
Every loan must match dws_mod_loan_td; mismatches fail with examples.
"""

import csv  
import sys  
from collections import defaultdict  

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


def is_dlq60(status):  
    return status == "RA" or (status.isdigit() and int(status) >= 2)


def state(status, zbc):  
    if zbc:  
        return EXIT[zbc]
    if status == "RA":  
        return "REO"
    if not status.isdigit():  
        return "UNK"
    return ["C", "30", "60", "90"][int(status)] if int(status) < 4 else "120+"


def summarize(recs):  
    mods = [p for p, _, _, flag in recs if flag == "Y"]  
    if not mods:
        return None
    first = min(mods)  
    by_after = {months(p) - months(first): (s, z) for p, s, z, _ in recs}
    before = [is_dlq60(s) for k, (s, _) in by_after.items() if -12 <= k <= -1]
    redefault = [k for k, (s, _) in by_after.items() if 1 <= k <= 12 and is_dlq60(s)]
    last_k = max(by_after)  
    if 12 in by_after:  
        s12 = state(*by_after[12])
    elif by_after[last_k][1] and last_k < 12:  
        s12 = state(*by_after[last_k])
    else:  
        s12 = None
    redefault_period = None
    if redefault:  
        m = months(first) + min(redefault) - 1
        redefault_period = f"{m // 12}{m % 12 + 1:02d}"
    return (
        first,
        len(mods),
        ("Y" if any(before) else "N") if before else None,
        redefault_period,
        s12,
    )


def main(release_id, perf, perf_hdr):
    with open(perf_hdr, encoding="utf-8") as f:  
        header = f.readline().rstrip("\r\n").split("|")
    cols = [
        header.index(c)
        for c in (
            "LOAN IDENTIFIER",
            "PERIOD",
            "CURRENT LOAN DELINQUENCY STATUS",
            "ZERO BALANCE CODE",
            "MODIFICATION FLAG",
        )
    ]
    rows = defaultdict(list)  
    with open(perf, encoding="utf-8", newline="") as f:
        for line_no, r in enumerate(
            csv.reader(f, delimiter="|", quoting=csv.QUOTE_NONE), start=1
        ):
            if len(r) != len(header):
                raise ValueError(f"Line {line_no} has {len(r)} columns; header requires {len(header)} columns")
            loan, period, status, zbc, flag = (r[i] for i in cols)
            rows[loan].append((period, status, zbc, flag))
    if not rows:
        raise ValueError(f"{perf} is empty")
    expected = {}  
    for loan, recs in rows.items():
        result = summarize(recs)
        if result:
            expected[loan] = result
    with connect() as conn, conn.cursor() as cur:  
        cur.execute(
            "select loan_identifier, to_char(first_mod_period, 'YYYYMM'), mod_count,"
            " is_dlq60_before_mod, to_char(first_redefault_period, 'YYYYMM'),"
            " state_12m from dws_mod_loan_td where release_id = :r",
            r=release_id,
        )
        
        db = {r[0]: tuple(r[1:]) for r in cur if r[0] in rows}
    bad = [(k, expected.get(k), db.get(k)) for k in expected.keys() | db.keys()]
    bad = [b for b in bad if b[1] != b[2]]  
    if bad:
        for k, e, d in sorted(bad)[:5]:
            print(f"Mismatch {k}: Python {e}, database {d}", file=sys.stderr)
        raise RuntimeError(f"{len(bad)} loans differ")
    print(f"{release_id} {perf}: {len(expected)} modified loans all match")


if __name__ == "__main__":  
    if len(sys.argv) != 4:  
        sys.exit(__doc__)  
    main(*sys.argv[1:])
