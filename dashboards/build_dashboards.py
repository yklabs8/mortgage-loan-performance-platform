"""Generate the Tableau workbook of the three analyses (roll rates, vintage curves, modification outcomes) from CSV exports.

Usage: python3 dashboards/build_dashboards.py <CSV directory> <output .twb> [--relative]
Data: python/export_dashboard_csv.py exports the analysis tables of one release from Oracle into the CSV directory.
The workbook stores the CSV directory as an absolute path; with --relative the directory is given relative to the workbook's folder
and stored that way (the copy in this repository was made with: build_dashboards.py data dashboards/loan_risk_dashboards.twb --relative). Rates are always "sum the counts, then divide"
(docs/metric_definitions.md); subgroup rates are never averaged.
"""

import csv
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] != "--relative"):
    sys.exit(__doc__)
OUT = Path(sys.argv[2])
RELATIVE = len(sys.argv) == 4
# With --relative the CSV directory is read relative to the workbook's folder and stored as given
DATA = OUT.parent / sys.argv[1] if RELATIVE else Path(sys.argv[1])
DIRECTORY = sys.argv[1] if RELATIVE else str(DATA.resolve())

INT_COLS = {
    "months_on_book",
    "cohort_loans",
    "eligible_loans",
    "cum_dlq60_loans",
    "loan_count",
    "from_state_order",
    "to_state_order",
    "modified_loans",
    "observable_12m_loans",
    "redefault_12m_loans",
    "current_12m_loans",
    "prepaid_12m_loans",
    "dlq60_loans",
    "cured_loans",
    "cure_events",
    "redefault_loans",
}
REAL_COLS = {"cum_dlq60_rate", "redefault_12m_rate", "current_12m_rate", "cure_rate"}
DATE_COLS = {"monthly_reporting_period"}

# Data sources: key -> analysis table
SOURCES = {
    "trans": "ads_dlq_transition_monthly",
    "curve": "ads_vintage_dlq60_curve",
    "vseg": "ads_vintage_dlq60_segment",
    "mod": "ads_modification_outcome",
    "modseg": "ads_modification_segment",
    "cure": "ads_cure_redefault_segment",
    "final": "ads_final_outcome_segment",
}

# Calculated fields: data source -> [(internal name, caption, type, role, formula, format)]
PAD = 'RIGHT("0" + STR([{o}]), 2) + " " + [{s}]'
CALCS = {
    "trans": [
        (
            "Calc_from",
            "From state",
            "string",
            "dimension",
            PAD.format(o="from_state_order", s="from_state"),
            None,
        ),
        (
            "Calc_to",
            "To state",
            "string",
            "dimension",
            PAD.format(o="to_state_order", s="to_state"),
            None,
        ),
        (
            "Calc_transition",
            "Transition",
            "string",
            "dimension",
            '[from_state] + " → " + [to_state]',
            None,
        ),
        (
            "Calc_from_total_all",
            "Loans in from state (all months)",
            "integer",
            "measure",
            "{FIXED [from_state] : SUM([loan_count])}",
            None,
        ),
        (
            "Calc_from_total_month",
            "Loans in from state (month)",
            "integer",
            "measure",
            "{FIXED [monthly_reporting_period], [from_state] : SUM([loan_count])}",
            None,
        ),
        (
            "Calc_roll_all",
            "Roll rate",
            "real",
            "measure",
            "SUM([loan_count]) / AVG([Calc_from_total_all])",
            "p0.0%",
        ),
        (
            "Calc_roll_month",
            "Monthly roll rate",
            "real",
            "measure",
            "SUM([loan_count]) / AVG([Calc_from_total_month])",
            "p0.0%",
        ),
    ],
    "curve": [
        (
            "Calc_vintage",
            "Vintage",
            "string",
            "dimension",
            '[origination_year] + "Q" + [origination_quarter]',
            None,
        ),
        (
            "Calc_rate",
            "Cum 60+ rate",
            "real",
            "measure",
            "SUM([cum_dlq60_loans]) / SUM([eligible_loans])",
            "p0.0%",
        ),
        (
            "Calc_cov",
            "Enough coverage",
            "boolean",
            "dimension",
            "[eligible_loans] >= 0.95 * [cohort_loans]",
            None,
        ),
    ],
    "vseg": [
        (
            "Calc_m36_cum",
            "60+ loans by month 36",
            "integer",
            "measure",
            "IF [months_on_book] = 36 THEN [cum_dlq60_loans] END",
            None,
        ),
        (
            "Calc_m36_elig",
            "Loans observed 36 months",
            "integer",
            "measure",
            "IF [months_on_book] = 36 THEN [eligible_loans] END",
            None,
        ),
        (
            "Calc_m36_rate",
            "Cum 60+ rate at month 36",
            "real",
            "measure",
            "SUM([Calc_m36_cum]) / SUM([Calc_m36_elig])",
            "p0.0%",
        ),
    ],
    "mod": [
        (
            "Calc_redef",
            "12-month re-default rate",
            "real",
            "measure",
            "SUM([redefault_12m_loans]) / SUM([observable_12m_loans])",
            "p0.0%",
        ),
    ],
    "modseg": [
        (
            "Calc_redef",
            "12-month re-default rate",
            "real",
            "measure",
            "SUM([redefault_12m_loans]) / SUM([observable_12m_loans])",
            "p0.0%",
        ),
    ],
    "cure": [
        (
            "Calc_cure",
            "Cure rate",
            "real",
            "measure",
            "SUM([cured_loans]) / SUM([dlq60_loans])",
            "p0.0%",
        ),
    ],
    "final": [
        (
            "Calc_seg_total",
            "Loans in segment",
            "integer",
            "measure",
            "{FIXED [segment_type], [segment_value] : SUM([loan_count])}",
            None,
        ),
        (
            "Calc_share",
            "Share of loans",
            "real",
            "measure",
            "SUM([loan_count]) / AVG([Calc_seg_total])",
            "p0.0%",
        ),
    ],
}


def header(table):
    path = DATA / f"{table}.csv"
    with open(path, encoding="utf-8", newline="") as f:
        return next(csv.reader(f))


def dtype(col):
    if col in INT_COLS:
        return "integer"
    if col in REAL_COLS:
        return "real"
    if col in DATE_COLS:
        return "date"
    return "string"


def a(v):
    return quoteattr(v)


def calc_xml(name, caption, typ, role, formula, fmt):
    kind = "quantitative" if role == "measure" else "nominal"
    f = f" default-format={a(fmt)}" if fmt else ""
    return (
        f"<column caption={a(caption)} datatype={a(typ)}{f} name={a('[' + name + ']')} role={a(role)} "
        f"type={a(kind)}><calculation class='tableau' formula={a(formula)} /></column>"
    )


def base_cols(key):
    out = []
    for col in header(SOURCES[key]):
        t = dtype(col)
        role = "measure" if t in ("integer", "real") else "dimension"
        kind = "quantitative" if role == "measure" or t == "date" else "nominal"
        out.append(
            f"<column datatype={a(t)} name={a('[' + col + ']')} role={a(role)} type={a(kind)} />"
        )
    return out


def datasource(key):
    table = SOURCES[key]
    fname = f"{table}.csv"
    rel_cols = "".join(
        f"<column datatype={a(dtype(c))} name={a(c)} ordinal='{i}' />"
        for i, c in enumerate(header(table))
    )
    calcs = "".join(calc_xml(*c) for c in CALCS.get(key, []))
    return (
        f"<datasource caption={a(fname)} inline='true' name='federated.{key}' version='18.1'>"
        "<connection class='federated'><named-connections>"
        f"<named-connection caption={a(fname)} name='textscan.{key}'>"
        f"<connection class='textscan' directory={a(DIRECTORY)} filename={a(fname)} password='' server='' />"
        "</named-connection></named-connections>"
        f"<relation connection='textscan.{key}' name={a(fname)} table={a('[' + fname.replace('.', '#') + ']')} type='table'>"
        f"<columns character-set='UTF-8' header='yes' locale='en_US' separator=','>{rel_cols}</columns>"
        "</relation></connection>" + "".join(base_cols(key)) + calcs + "</datasource>"
    )


def inst(key, col, deriv, kind):
    """Column instance name, such as [federated.trans].[none:Calc_from:nk]."""
    prefix = {"None": "none", "Sum": "sum", "User": "usr", "Month-Trunc": "tmn"}[deriv]
    return f"[federated.{key}].[{prefix}:{col}:{kind}]"


def inst_xml(col, deriv, kind):
    prefix = {"None": "none", "Sum": "sum", "User": "usr", "Month-Trunc": "tmn"}[deriv]
    typ = "quantitative" if kind == "qk" else ("ordinal" if kind == "ok" else "nominal")
    return (
        f"<column-instance column={a('[' + col + ']')} derivation={a(deriv)} "
        f"name={a('[' + prefix + ':' + col + ':' + kind + ']')} pivot='key' type={a(typ)} />"
    )


def member_filter(key, col_inst_short, members, exclude=False):
    level = col_inst_short
    mem = "".join(
        f"<groupfilter function='member' level={a(level)} member={a(chr(34) + m + chr(34))} />"
        for m in members
    )
    if exclude:
        inner = (
            f"<groupfilter function='except' user:ui-domain='database' user:ui-enumeration='exclusive' "
            f"user:ui-marker='enumerate'><groupfilter function='level-members' level={a(level)} />"
        )
        inner += (
            mem
            if len(members) == 1
            else f"<groupfilter function='union'>{mem}</groupfilter>"
        ) + "</groupfilter>"
    elif len(members) == 1:
        inner = mem.replace(
            "/>",
            "user:ui-domain='database' user:ui-enumeration='inclusive' user:ui-marker='enumerate' />",
        )
    else:
        inner = (
            f"<groupfilter function='union' user:ui-domain='database' user:ui-enumeration='inclusive' "
            f"user:ui-marker='enumerate'>{mem}</groupfilter>"
        )
    return f"<filter class='categorical' column={a(f'[federated.{key}].{level}')}>{inner}</filter>"


def bool_filter(key, level):
    return (
        f"<filter class='categorical' column={a(f'[federated.{key}].{level}')}>"
        f"<groupfilter function='member' level={a(level)} member='true' user:ui-domain='database' "
        f"user:ui-enumeration='inclusive' user:ui-marker='enumerate' /></filter>"
    )


def worksheet(
    name,
    title,
    key,
    instances,
    rows,
    cols,
    mark,
    encodings="",
    filters=(),
    axis_titles=(),
):
    deps = "".join(base_cols(key)) + "".join(calc_xml(*c) for c in CALCS.get(key, []))
    deps += "".join(inst_xml(*i) for i in instances)
    fxml = "".join(f for f, _ in filters)
    slices = "".join(f"<column>{s}</column>" for _, s in filters)
    slices = f"<slices>{slices}</slices>" if slices else ""
    axes = "".join(
        f"<format attr='title' class='0' field={a(f)} scope={a(s)} value={a(v)} />"
        for f, s, v in axis_titles
    )
    style = (
        f"<style><style-rule element='axis'>{axes}</style-rule></style>"
        if axes
        else "<style />"
    )
    return (
        f"<worksheet name={a(name)}><layout-options><title><formatted-text>"
        f"<run bold='true' fontsize='13'>{escape(title)}</run></formatted-text></title></layout-options>"
        f"<table><view><datasources><datasource caption={a(SOURCES[key])} name='federated.{key}' /></datasources>"
        f"<datasource-dependencies datasource='federated.{key}'>{deps}</datasource-dependencies>"
        f"{fxml}{slices}<aggregation value='true' /></view>{style}"
        f"<panes><pane selection-relaxation-option='selection-relaxation-allow'><view><breakdown value='auto' /></view>"
        f"<mark class={a(mark)} /><encodings>{encodings}</encodings></pane></panes>"
        f"<rows>{rows}</rows><cols>{cols}</cols></table></worksheet>"
    )


def escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


with open(DATA / "ads_vintage_dlq60_curve.csv", encoding="utf-8", newline="") as f:
    YEARS = sorted({row["origination_year"] for row in csv.DictReader(f)})
SRC = "Freddie Mac sample, origination years " + ", ".join(YEARS)
sheets = []
windows = []

# ---------- 1. Roll matrix ----------
k = "trans"
fr, to, roll = (
    inst(k, "Calc_from", "None", "nk"),
    inst(k, "Calc_to", "None", "nk"),
    inst(k, "Calc_roll_all", "User", "qk"),
)
sheets.append(
    worksheet(
        "Roll Matrix",
        f"Monthly roll rates, all months pooled ({SRC})",
        k,
        [
            ("Calc_from", "None", "nk"),
            ("Calc_to", "None", "nk"),
            ("Calc_roll_all", "User", "qk"),
        ],
        fr,
        to,
        "Square",
        f"<color column={a(roll)} /><text column={a(roll)} />",
    )
)

# ---------- 2. Key roll rates by month ----------
per, tr, rm = (
    inst(k, "monthly_reporting_period", "Month-Trunc", "qk"),
    inst(k, "Calc_transition", "None", "nk"),
    inst(k, "Calc_roll_month", "User", "qk"),
)
sheets.append(
    worksheet(
        "Monthly Roll Rates",
        "Key monthly roll rates over time",
        k,
        [
            ("monthly_reporting_period", "Month-Trunc", "qk"),
            ("Calc_transition", "None", "nk"),
            ("Calc_roll_month", "User", "qk"),
        ],
        rm,
        per,
        "Line",
        f"<color column={a(tr)} />",
        filters=[
            (
                member_filter(
                    k,
                    "[none:Calc_transition:nk]",
                    ["C → 30", "30 → 60", "60 → 90", "30 → C"],
                ),
                tr,
            )
        ],
        axis_titles=[
            (per, "cols", "Reporting month"),
            (rm, "rows", "Share of last month's loans"),
        ],
    )
)

# ---------- 3. Cumulative 60+ curve ----------
k = "curve"
mob, rate, vin, cov = (
    inst(k, "months_on_book", "None", "qk"),
    inst(k, "Calc_rate", "User", "qk"),
    inst(k, "Calc_vintage", "None", "nk"),
    inst(k, "Calc_cov", "None", "nk"),
)
sheets.append(
    worksheet(
        "Vintage Curve",
        "Cumulative 60+ delinquency rate by origination quarter",
        k,
        [
            ("months_on_book", "None", "qk"),
            ("Calc_rate", "User", "qk"),
            ("Calc_vintage", "None", "nk"),
            ("Calc_cov", "None", "nk"),
        ],
        rate,
        mob,
        "Line",
        f"<color column={a(vin)} />",
        filters=[(bool_filter(k, "[none:Calc_cov:nk]"), cov)],
        axis_titles=[
            (mob, "cols", "Months on book (points with ≥95% of the quarter observed)"),
            (rate, "rows", "Cumulative 60+ delinquency rate"),
        ],
    )
)

# ---------- 4. Cumulative 60+ at month 36, by attribute ----------
k = "vseg"
st, sv, m36 = (
    inst(k, "segment_type", "None", "nk"),
    inst(k, "segment_value", "None", "nk"),
    inst(k, "Calc_m36_rate", "User", "qk"),
)
sheets.append(
    worksheet(
        "Vintage by Segment",
        "Cumulative 60+ rate at month 36, by loan attribute",
        k,
        [
            ("segment_type", "None", "nk"),
            ("segment_value", "None", "nk"),
            ("Calc_m36_rate", "User", "qk"),
        ],
        f"({st} / {sv})",
        m36,
        "Bar",
        f"<text column={a(m36)} />",
        filters=[
            (member_filter(k, "[none:segment_type:nk]", ["STATE"], exclude=True), st)
        ],
        axis_titles=[(m36, "cols", "Cumulative 60+ rate at month 36")],
    )
)

# ---------- 5. 12-month re-default after modification, by modification year and prior status ----------
k = "mod"
fm, grp, rd = (
    inst(k, "first_mod_year", "None", "nk"),
    inst(k, "before_mod_group", "None", "nk"),
    inst(k, "Calc_redef", "User", "qk"),
)
sheets.append(
    worksheet(
        "Re-default by Mod Year",
        "12-month re-default rate after first modification",
        k,
        [
            ("first_mod_year", "None", "nk"),
            ("before_mod_group", "None", "nk"),
            ("Calc_redef", "User", "qk"),
        ],
        rd,
        f"({fm} / {grp})",
        "Bar",
        f"<color column={a(grp)} />",
        axis_titles=[
            (rd, "rows", "Re-default within 12 months (loans observed 12 months)")
        ],
    )
)

# ---------- 6. Re-default by attribute ----------
k = "modseg"
st, sv, rd = (
    inst(k, "segment_type", "None", "nk"),
    inst(k, "segment_value", "None", "nk"),
    inst(k, "Calc_redef", "User", "qk"),
)
sheets.append(
    worksheet(
        "Re-default by Segment",
        "12-month re-default rate after modification, by loan attribute",
        k,
        [
            ("segment_type", "None", "nk"),
            ("segment_value", "None", "nk"),
            ("Calc_redef", "User", "qk"),
        ],
        f"({st} / {sv})",
        rd,
        "Bar",
        f"<text column={a(rd)} />",
        filters=[
            (member_filter(k, "[none:segment_type:nk]", ["STATE"], exclude=True), st)
        ],
        axis_titles=[(rd, "cols", "12-month re-default rate")],
    )
)

# ---------- 7. Cure rate by attribute ----------
k = "cure"
st, sv, cr = (
    inst(k, "segment_type", "None", "nk"),
    inst(k, "segment_value", "None", "nk"),
    inst(k, "Calc_cure", "User", "qk"),
)
sheets.append(
    worksheet(
        "Cure Rate by Segment",
        "Cure rate of loans that reached 60+ (3 straight current months), by loan attribute",
        k,
        [
            ("segment_type", "None", "nk"),
            ("segment_value", "None", "nk"),
            ("Calc_cure", "User", "qk"),
        ],
        f"({st} / {sv})",
        cr,
        "Bar",
        f"<text column={a(cr)} />",
        filters=[
            (member_filter(k, "[none:segment_type:nk]", ["STATE"], exclude=True), st)
        ],
        axis_titles=[(cr, "cols", "Cure rate")],
    )
)

# ---------- 8. Final outcome share by attribute ----------
k = "final"
st, sv, fs, sh = (
    inst(k, "segment_type", "None", "nk"),
    inst(k, "segment_value", "None", "nk"),
    inst(k, "final_state", "None", "nk"),
    inst(k, "Calc_share", "User", "qk"),
)
sheets.append(
    worksheet(
        "Final Outcome by Segment",
        "Final outcome as of the latest release, by loan attribute",
        k,
        [
            ("segment_type", "None", "nk"),
            ("segment_value", "None", "nk"),
            ("final_state", "None", "nk"),
            ("Calc_share", "User", "qk"),
        ],
        f"({st} / {sv})",
        sh,
        "Bar",
        f"<color column={a(fs)} />",
        filters=[
            (member_filter(k, "[none:segment_type:nk]", ["STATE"], exclude=True), st)
        ],
        axis_titles=[(sh, "cols", "Share of loans in the segment")],
    )
)

# ---------- Dashboards ----------
DASH = [
    (
        "Roll Rates",
        [
            ("Roll Matrix", None),
            ("Monthly Roll Rates", inst("trans", "Calc_transition", "None", "nk")),
        ],
    ),
    (
        "Vintage Delinquency",
        [
            ("Vintage Curve", inst("curve", "Calc_vintage", "None", "nk")),
            ("Vintage by Segment", None),
        ],
    ),
    (
        "Modification Outcomes",
        [
            ("Re-default by Mod Year", inst("mod", "before_mod_group", "None", "nk")),
            ("Re-default by Segment", None),
        ],
    ),
    (
        "Cure and Final Outcome",
        [
            ("Cure Rate by Segment", None),
            ("Final Outcome by Segment", inst("final", "final_state", "None", "nk")),
        ],
    ),
]


def dashboard(name, parts):
    zones, zid = [], 2
    # Two columns; a column with a legend keeps 12% of its height below for it
    for i, (sheet, legend) in enumerate(parts):
        x = i * 50000
        h = 88000 if legend else 100000
        zones.append(
            f"<zone h='{h}' id='{zid}' name={a(sheet)} w='50000' x='{x}' y='0' />"
        )
        zid += 1
        if legend:
            zones.append(
                f"<zone h='12000' id='{zid}' name={a(sheet)} pane-specification-id='0' param={a(legend)} "
                f"type-v2='color' w='50000' x='{x}' y='88000' />"
            )
            zid += 1
    return (
        f"<dashboard name={a(name)}><style /><size maxheight='900' maxwidth='1600' minheight='900' minwidth='1600' />"
        f"<zones><zone h='100000' id='1' type-v2='layout-basic' w='100000' x='0' y='0'>{''.join(zones)}</zone>"
        "</zones></dashboard>"
    )


for s in [w.split("name=", 1)[1].split(">", 1)[0] for w in sheets]:
    windows.append(
        f"<window class='worksheet' name={s}><cards><edge name='left'><strip size='160'>"
        "<card type='filters' /><card type='marks' /></strip></edge></cards></window>"
    )
for name, _ in DASH:
    windows.append(
        f"<window class='dashboard' maximized='true' name={a(name)}><viewpoints /></window>"
    )

xml = (
    "<?xml version='1.0' encoding='utf-8' ?>\n"
    "<workbook source-build='2026.2.0 (20262.26.0819.2015)' source-platform='mac' version='18.1' "
    "xmlns:user='http://www.tableausoftware.com/xml/user'><preferences />"
    f"<datasources>{''.join(datasource(k) for k in SOURCES)}</datasources>"
    f"<worksheets>{''.join(sheets)}</worksheets>"
    f"<dashboards>{''.join(dashboard(n, p) for n, p in DASH)}</dashboards>"
    f"<windows>{''.join(windows)}</windows></workbook>\n"
)
OUT.write_text(xml, encoding="utf-8")
print(f"{OUT}: {len(sheets)} sheets, {len(DASH)} dashboards, data {DIRECTORY}")
