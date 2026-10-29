"""Independently recompute loan bands from raw values and compare each dimension row."""

from collections import Counter

from db import connect


def fico_band(value):
    if value is None or value == 9999:
        return "UNKNOWN"
    if value < 620:
        return "<620"
    if value < 680:
        return "[620,680)"
    if value < 740:
        return "[680,740)"
    return ">=740"


def ltv_band(value):
    if value is None or value == 999:
        return "UNKNOWN"
    if value <= 60:
        return "<=60"
    if value <= 80:
        return "(60,80]"
    if value <= 90:
        return "(80,90]"
    if value <= 97:
        return "(90,97]"
    return ">97"


def main():
    
    assert [fico_band(n) for n in (None, 9999, 619, 620, 679, 680, 739, 740)] == [
        "UNKNOWN",
        "UNKNOWN",
        "<620",
        "[620,680)",
        "[620,680)",
        "[680,740)",
        "[680,740)",
        ">=740",
    ]
    assert [ltv_band(n) for n in (None, 999, 60, 61, 80, 81, 90, 91, 97, 98)] == [
        "UNKNOWN",
        "UNKNOWN",
        "<=60",
        "(60,80]",
        "(60,80]",
        "(80,90]",
        "(80,90]",
        "(90,97]",
        "(90,97]",
        ">97",
    ]
    releases = ("R45", "R46", "R47")
    totals = Counter()
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "select release_id, loan_identifier, classic_fico, fico_band, "
            "original_loan_to_value_ltv, ltv_band from dim_loan "
            "where release_id in (:r1, :r2, :r3, :r4)",
            dict(zip(("r1", "r2", "r3", "r4"), releases, strict=True)),
        )
        for release, loan, fico, stored_fico, ltv, stored_ltv in cur:
            expected = (fico_band(fico), ltv_band(ltv))
            if (stored_fico, stored_ltv) != expected:
                raise AssertionError(
                    f"{release}/{loan}: DIM {(stored_fico, stored_ltv)} != Python {expected}"
                )
            totals[release] += 1
    missing = set(releases) - totals.keys()
    if missing:
        raise AssertionError(f"Missing release: {sorted(missing)}")
    for release in releases:
        print(f"{release}: {totals[release]} loan bands match row by row")


if __name__ == "__main__":
    main()
