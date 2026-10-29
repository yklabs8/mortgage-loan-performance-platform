# Recompute bands, states, vintage curves, modification outcomes, cure events and final outcomes from raw files without using warehouse classification views. Each of nine attributes is grouped independently, never as a joint cross product.
"""Independently recompute segmented ADS from raw origination, monthly and Census files.

Usage: python python/reconcile_segment.py RELEASE ORIG ORIG_HEADER PERF PERF_HEADER CENSUS_DIR
New layout only; compares every cell without reading loan dimensions or segmentation views.
"""

import csv
import sys
from collections import Counter, defaultdict
from itertools import pairwise
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

from db import connect
from reconcile_loan_bands import fico_band, ltv_band
from reconcile_modification import is_dlq60, summarize
from reconcile_transition import EXIT, months, state

NS = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
SEGMENT_FIELDS = {
    "FICO": "CLASSIC FICO",
    "LTV": "ORIGINAL LOAN-TO-VALUE (LTV)",
    "STATE": "PROPERTY STATE",
    "CHANNEL": "CHANNEL",
    "LOAN_PURPOSE": "LOAN PURPOSE",
    "PROPERTY_TYPE": "PROPERTY TYPE",
    "AMORTIZATION": "AMORTIZATION TYPE",
    "HARP": "HARP INDICATOR",
}


def header_columns(path):
    with open(path, encoding="utf-8") as handle:
        return handle.readline().rstrip("\r\n").split("|")


def data_rows(path, header):
    with open(path, encoding="utf-8", newline="") as handle:
        for line_no, values in enumerate(
            csv.reader(handle, delimiter="|", quoting=csv.QUOTE_NONE), start=1
        ):
            if len(values) != len(header):
                raise ValueError(
                    f"{path} item {line_no} has {len(values)} columns; header requires {len(header)} columns"
                )
            yield dict(zip(header, values, strict=True))


def census_regions(directory):
    directory = Path(directory)
    with (directory / "state.txt").open(encoding="utf-8") as handle:
        fips_to_state = {
            row["STATE"]: row["STUSAB"] for row in csv.DictReader(handle, delimiter="|")
        }
    workbook = directory / "state-geocodes-v2023.xlsx"
    with ZipFile(workbook) as archive:
        strings_xml = ET.fromstring(archive.read("xl/sharedStrings.xml"))
        strings = [
            "".join(element.text or "" for element in item.findall(".//x:t", NS))
            for item in strings_xml.findall("x:si", NS)
        ]
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
    region_names = {}
    by_state = {}
    for row in sheet.findall(".//x:sheetData/x:row", NS):
        values = {}
        for cell in row.findall("x:c", NS):
            value = cell.find("x:v", NS)
            if value is None:
                continue
            item = value.text
            if cell.attrib.get("t") == "s":
                item = strings[int(item)]
            values[cell.attrib["r"].rstrip("0123456789")] = item
        if values.get("C") == "00" and values.get("B") == "0":
            region_names[values["A"]] = values["D"].removesuffix(" Region")
        elif values.get("C") in fips_to_state:
            by_state[fips_to_state[values["C"]]] = values["A"]
    return {state: region_names[code] for state, code in by_state.items()}


def segments(row, regions):
    values = {}
    for name, field in SEGMENT_FIELDS.items():
        value = row[field] or None
        if name == "FICO":
            value = fico_band(int(value) if value else None)
        elif name == "LTV":
            value = ltv_band(int(value) if value else None)
        values[name] = value or "UNKNOWN"
    state_code = row["PROPERTY STATE"] or "UNKNOWN"
    values["REGION"] = regions.get(state_code, "Not in a Census region")
    if state_code == "UNKNOWN":
        values["REGION"] = "UNKNOWN"
    return values


def assert_cells(name, expected, actual):
    bad = [
        (key, expected.get(key), actual.get(key))
        for key in expected.keys() | actual.keys()
        if expected.get(key) != actual.get(key)
    ]
    if bad:
        raise AssertionError(f"{name} {len(bad)} cells differ: {sorted(bad)[:5]}")
    print(f"{name}: {len(expected)} cells match")


def cure_redefault_events(records):
    """Find cure events and subsequent 60+ relapses from raw sequences; missing months break continuity."""
    awaiting_cure = False
    current_streak = 0
    previous_month = None
    cures = []
    first_redefault = None
    for period, status, zero_balance_code in sorted(records):
        month = months(period)
        if previous_month is None or month - previous_month != 1:
            current_streak = 0
        if is_dlq60(status):
            if cures and first_redefault is None:
                first_redefault = period
            awaiting_cure = True
            current_streak = 0
        elif (
            status.isdigit()
            and int(status) == 0
            and not zero_balance_code
            and awaiting_cure
        ):
            current_streak += 1
            if current_streak == 3:
                cures.append(period)
                awaiting_cure = False
        else:
            current_streak = 0
        previous_month = month
    return cures, first_redefault


def curve_from_raw(loans, first_pay, first_hit, cutoff):
    cohort = Counter()
    reach = defaultdict(Counter)
    events = defaultdict(Counter)
    quarter_max = {}
    for loan, attrs in loans.items():
        year = 1999 if loan[1:3] == "99" else 2000 + int(loan[1:3])
        quarter = int(loan[4])
        max_mob = cutoff - first_pay[loan] + 1
        quarter_max[(year, quarter)] = max(quarter_max.get((year, quarter), 0), max_mob)
        for kind, value in attrs.items():
            group = (year, quarter, kind, value)
            cohort[group] += 1
            if max_mob >= 1:
                reach[group][max_mob] += 1
            hit = first_hit.get(loan)
            if hit is not None and max(1, hit) <= max_mob:
                events[group][max(1, hit)] += 1
                events[group][max_mob + 1] -= 1
    result = {}
    for group, size in cohort.items():
        eligible = sum(reach[group].values())
        hit_total = 0
        for mob in range(1, quarter_max[group[:2]] + 1):
            if mob > 1:
                eligible -= reach[group][mob - 1]
            hit_total += events[group][mob]
            key = (group[0], group[1], mob, group[2], group[3])
            result[key] = (size, eligible, hit_total)
    return result


def modification_from_raw(loans, records):
    result = defaultdict(lambda: [0, 0, 0, 0, 0])
    for loan, attrs in loans.items():
        summary = summarize(records[loan])
        if summary is None:
            continue
        first, _, before, redefault, month12 = summary
        year = 1999 if loan[1:3] == "99" else 2000 + int(loan[1:3])
        before_group = {"Y": "DLQ60", "N": "NOT_DLQ60"}.get(before, "NO_PRIOR")
        for kind, value in attrs.items():
            key = (year, int(first[:4]), before_group, kind, value)
            counts = result[key]
            counts[0] += 1
            counts[1] += month12 is not None
            counts[2] += month12 is not None and redefault is not None
            counts[3] += month12 == "C"
            counts[4] += month12 == "PREPAID"
    return {key: tuple(value) for key, value in result.items()}


def cure_from_raw(loans, records):
    result = defaultdict(lambda: [0, 0, 0, 0])
    for loan, attrs in loans.items():
        monthly = [(p, status, zbc) for p, status, zbc, _ in records[loan]]
        cures, redefault = cure_redefault_events(monthly)
        has_dlq60 = any(is_dlq60(status) for _, status, _ in monthly)
        year = 1999 if loan[1:3] == "99" else 2000 + int(loan[1:3])
        for kind, value in attrs.items():
            counts = result[(year, kind, value)]
            counts[0] += has_dlq60
            counts[1] += bool(cures)
            counts[2] += len(cures)
            counts[3] += redefault is not None
    return {key: tuple(counts) for key, counts in result.items()}


def main(release, orig_path, orig_header, perf_path, perf_header, census_dir):
    regions = census_regions(census_dir)
    orig_columns = header_columns(orig_header)
    perf_columns = header_columns(perf_header)
    loans = {}
    first_pay = {}
    for row in data_rows(orig_path, orig_columns):
        loan = row["LOAN IDENTIFIER"]
        if loan in loans:
            raise ValueError(f"Duplicate origination loan ID: {loan}")
        loans[loan] = segments(row, regions)
        first_pay[loan] = months(row["FIRST PAYMENT DATE"])
    if not loans:
        raise ValueError("Origination file is empty")
    years = {1999 if loan[1:3] == "99" else 2000 + int(loan[1:3]) for loan in loans}
    perf = defaultdict(list)
    mod_records = defaultdict(list)
    first_hit = {}
    cutoff = 0
    for row in data_rows(perf_path, perf_columns):
        loan = row["LOAN IDENTIFIER"]
        if loan not in loans:
            raise ValueError(f"Performance loan missing from origination file: {loan}")
        period = row["PERIOD"]
        status = row["CURRENT LOAN DELINQUENCY STATUS"]
        zbc = row["ZERO BALANCE CODE"]
        perf[loan].append((period, state(status, zbc)))
        mod_records[loan].append((period, status, zbc, row["MODIFICATION FLAG"]))
        cutoff = max(cutoff, months(period))
        if is_dlq60(status):
            mob = months(period) - first_pay[loan] + 1
            first_hit[loan] = min(first_hit.get(loan, mob), mob)
    if cutoff == 0:
        raise ValueError("Performance file is empty")
    plain = Counter()
    grouped = Counter()
    endings = Counter()
    for loan, attrs in loans.items():
        year = 1999 if loan[1:3] == "99" else 2000 + int(loan[1:3])
        records = sorted(perf[loan])
        for (previous_period, previous_state), (period, current_state) in pairwise(
            records
        ):
            if months(period) - months(previous_period) != 1:
                continue
            plain[(year, period, previous_state, current_state)] += 1
            for kind, value in attrs.items():
                grouped[(year, period, previous_state, current_state, kind, value)] += 1
        final = (
            records[-1][1] if records and records[-1][1] in EXIT.values() else "ACTIVE"
        )
        for kind, value in attrs.items():
            endings[(year, kind, value, final)] += 1
    curve = curve_from_raw(loans, first_pay, first_hit, cutoff)
    modifications = modification_from_raw(loans, mod_records)
    cures = cure_from_raw(loans, mod_records)

    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "select origination_year, to_char(monthly_reporting_period, 'YYYYMM'), "
            "from_state, to_state, loan_count from ads_dlq_transition_monthly "
            "where release_id = :release",
            release=release,
        )
        db_plain = {(y, p, a, b): count for y, p, a, b, count in cur if y in years}
        cur.execute(
            "select origination_year, to_char(monthly_reporting_period, 'YYYYMM'), "
            "from_state, to_state, segment_type, segment_value, loan_count "
            "from ads_dlq_transition_segment where release_id = :release",
            release=release,
        )
        db_grouped = {
            (y, p, a, b, kind, value): count
            for y, p, a, b, kind, value, count in cur
            if y in years
        }
        cur.execute(
            "select origination_year, segment_type, segment_value, final_state, "
            "loan_count from ads_final_outcome_segment where release_id = :release",
            release=release,
        )
        db_endings = {
            (y, kind, value, final): count
            for y, kind, value, final, count in cur
            if y in years
        }
        cur.execute(
            "select origination_year, origination_quarter, months_on_book, "
            "segment_type, segment_value, cohort_loans, eligible_loans, "
            "cum_dlq60_loans from ads_vintage_dlq60_segment "
            "where release_id = :release",
            release=release,
        )
        db_curve = {
            (y, q, mob, kind, value): (cohort, eligible, hit)
            for y, q, mob, kind, value, cohort, eligible, hit in cur
            if y in years
        }
        cur.execute(
            "select origination_year, first_mod_year, before_mod_group, "
            "segment_type, segment_value, modified_loans, observable_12m_loans, "
            "redefault_12m_loans, current_12m_loans, prepaid_12m_loans "
            "from ads_modification_segment where release_id = :release",
            release=release,
        )
        db_modifications = {
            (y, mod_year, before, kind, value): tuple(counts)
            for y, mod_year, before, kind, value, *counts in cur
            if y in years
        }
        cur.execute(
            "select origination_year, segment_type, segment_value, "
            "dlq60_loans, cured_loans, cure_events, redefault_loans, cure_rate "
            "from ads_cure_redefault_segment where release_id = :release",
            release=release,
        )
        db_cures = {}
        for year, kind, value, denominator, cured, events, redefault, rate in cur:
            if year not in years:
                continue
            key = (year, kind, value)
            db_cures[key] = (denominator, cured, events, redefault)
            expected_counts = cures.get(key, (0, 0, 0, 0))
            expected_rate = (
                expected_counts[1] / expected_counts[0] if expected_counts[0] else None
            )
            if expected_rate is None:
                if rate is not None:
                    raise AssertionError(f"Cure rate must be NULL when its denominator is zero: {key} {rate}")
            elif rate is None or abs(float(rate) - expected_rate) > 1e-12:
                raise AssertionError(f"Cure rate mismatch: {key} {expected_rate} {rate}")
    assert_cells("Raw-file base transitions", plain, db_plain)
    assert_cells("Raw-file segmented transitions", grouped, db_grouped)
    assert_cells("Raw-file final outcomes", endings, db_endings)
    assert_cells("Raw-file segmented cumulative curves", curve, db_curve)
    assert_cells("Raw-file segmented modification outcomes", modifications, db_modifications)
    assert_cells("Raw-file segmented cure and relapse", cures, db_cures)
    for kind in SEGMENT_FIELDS.keys() | {"REGION"}:
        count = sum(value for key, value in grouped.items() if key[4] == kind)
        if count != sum(plain.values()):
            raise AssertionError(
                f"{kind} segment total {count}, raw transition total {sum(plain.values())}"
            )
    print(f"Each attribute total independently recomputed from raw files = {sum(plain.values())} transitions")


if __name__ == "__main__":
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    main(*sys.argv[1:])
