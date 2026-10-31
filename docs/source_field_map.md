# Data Dictionary: Source Fields Used

This dictionary covers the 14 Freddie Mac source fields that the current analyses, segmentation, and review rules depend on, plus two columns added by the ODS layer and two derived fields. All other source fields are loaded unchanged but are not interpreted here.

**Sources** (page numbers are PDF page numbers, which match the printed page footers):

- Current layout (Release 47, July 2026 and later): *Single-Family Loan-Level Dataset General User Guide*, Release 47, July 2026 ("UG"), and *File Layout July 2026* for positions, types, and lengths.
- Earlier layout (Release 46 and before): *General User Guide*, January 2026 ("earlier UG"), and *File Layout Pre-July 2026*.
- Mapping between the two layouts: *SFLLD Disclosure Changes Effective July 2026*, version 1.2 ("DC").

**Reading the type column**: the official type and maximum length come from the File Layout. The ODS stores every field as `varchar2` text of that length without conversion. The arrow shows the converted type in the warehouse dimension or fact table.

Uses marked *(later milestone)* belong to analyses that are not part of this version.

## 1. Origination data file (one row per loan)

These fields have the same position in both layouts; only some names changed.

| Pos. | Official name (current / earlier) | ODS column (`ods_orig` / `ods_orig_pre202607`) | Type, length → warehouse | Meaning | Values | Page (UG / earlier UG) | Used for |
|---|---|---|---|---|---|---|---|
| 1 | Classic FICO® / Credit Score | `classic_fico` / `credit_score` | Numeric 4 → number | Borrower credit score at origination | 300–850; `9999` = Not Available (also used for values < 300 or > 850) | p.4 / p.5; rename in DC p.2 | Credit-score segments *(later milestone)* |
| 2 | First Payment Date | `first_payment_date` | Date 6 (YYYYMM) → date | Month of the first scheduled payment | YYYYMM | p.4 / p.5 | Months on book; denominator of the cumulative 60+ curve |
| 12 | Original Loan-to-Value (LTV) | `original_loan_to_value_ltv` | Numeric 3 → number | Loan amount divided by property value, in percent | 2018Q1 and prior: 6–105; 2018Q2 and later: 1–998; `999` = Not Available | p.6 / p.7 | LTV segments *(later milestone)* |
| 14 | Channel | `channel` | Alpha 1 → varchar2(1) | Who originated the loan | `R` Retail, `B` Broker, `C` Correspondent, `T` Third Party Origination – Not Specified, `9` Not Available | p.6–7 / p.7 | Channel segments *(later milestone)* |
| 17 | Property State | `property_state` | Alpha 2 → varchar2(2) | State or territory of the property | Two-letter code, e.g. `TX` | p.7 / p.8 | State segments *(later milestone)* |
| 18 | Property Type | `property_type` | Alpha 2 → varchar2(2) | Type of property securing the loan | `SF` Single-Family, `CO` Condominium, `PU` Planned Unit Development, `CP` Cooperative, `MH` Manufactured Housing, `99` Not Available | p.7 / p.8 | Property-type segments *(later milestone)* |
| 20 | Loan Identifier / Loan Sequence Number | `loan_identifier` / `loan_sequence_number` | Alpha Numeric 12 (`PYYQnXXXXXXX`) → varchar2(12) | Unique loan ID; characters 2–5 are the origination year and quarter | `P` product, `YYQn` origination year and quarter, 7 random digits | p.7–8 / p.8; rename in DC p.2 | Business key in every table; origination year and quarter (section 3) |
| 21 | Loan Purpose | `loan_purpose` | Alpha 1 → varchar2(1) | Purchase or refinance | `P` Purchase, `C` Cash-out Refinance, `N` No Cash-out Refinance, `R` Refinance – Not Specified, `9` Not Available | p.8 / p.8 | Loan-purpose segments *(later milestone)* |

## 2. Monthly performance data file (one row per loan per month)

These fields also have the same position in both layouts.

| Pos. | Official name (current / earlier) | ODS column (`ods_perf` / `ods_perf_pre202607`) | Type, length → warehouse | Meaning | Values | Page (UG / earlier UG) | Used for |
|---|---|---|---|---|---|---|---|
| 1 | Loan Identifier / Loan Sequence Number | `loan_identifier` / `loan_sequence_number` | Alpha Numeric 12 → varchar2(12) | Same loan ID, links monthly rows to origination data | As above | p.10 / p.10; rename in DC p.4 | Business key of the monthly fact table |
| 2 | Period / Monthly Reporting Period | `monthly_reporting_period` (both layouts) | Date 6 (YYYYMM) → date | Month the row describes | YYYYMM | p.10 / p.10; rename in DC p.4 | Business key; months on book; join to the date dimension |
| 4 | Current Loan Delinquency Status | `current_loan_delinquency_status` | Alpha Numeric 3 → varchar2(3) | How far behind the borrower is this month | Current layout: `00` current or < 30 days, `01` 30–59 days, `02` 60–89 days, and so on, capped at `99`; `RA` REO Acquisition; `XX` Not Available. The earlier layout writes `0`, `1`, `2`; loading pads these to two digits | p.10 / p.10–11; layout difference in DC p.4 | 60+ delinquency flag; cumulative 60+ curve; review candidates; transitions *(later milestone)* |
| 5 | Loan Age | `loan_age` | Numeric 3 → number | Official count of scheduled payments since origination | Integer | p.10 / p.11 | **Deliberately not used** for months on book: it is reset after a modification, so months on book are computed from First Payment Date instead (metric definitions, section 2) |
| 8 | Modification Flag | `modification_flag` | Alpha 1 → varchar2(1) | Whether the loan's terms have been modified | `Y` modified this period, `P` modified in a prior period, null = not modified | p.11 / p.11 | Modification-outcome analysis *(later milestone)* |
| 9 | Zero Balance Code | `zero_balance_code` | Numeric 2 → varchar2(2) | Why the balance went to zero, i.e. how the loan ended | `01` Prepaid or Matured, `02` Third Party Sale, `03` Short Sale or Charge Off, `09` REO Disposition, `15` Whole Loan Sales, `16` Reperforming Loan Securitizations, `96` defect prior to credit event | p.11 / p.11 | Final outcomes and terminated state in transitions *(later milestone)* |
| 10 | Zero Balance Effective Date | `zero_balance_effective_date` | Date 6 (YYYYMM) → date | Month of the zero-balance event | YYYYMM | p.11 / p.12 | Termination month in the loan-level summary *(later milestone)* |

## 3. Columns not in the source files: load metadata and derived fields

| Name | Where | Meaning | Source |
|---|---|---|---|
| `release_id` | Every ODS, dimension, and fact table | Which publication the data came from (e.g. `R47`); supplied when loading | Internal convention (not an official rule); the dataset is periodically corrected and republished (UG p.2) |
| `source_file` | Every ODS table | Source file each row came from | Internal convention (not an official rule), for traceability |
| `origination_year` | Loan dimension | Characters 2–3 of the loan ID; `99` → 1999, otherwise 20YY | UG p.7–8 ("YYQn = origination year and quarter"); loans start in 1999 (UG p.2); the century mapping is an internal convention |
| `origination_quarter` | Loan dimension | Character 5 of the loan ID | As above |

## 4. Notes

- The earlier User Guide uses a three-column table layout; page numbers refer to the page where the field heading appears, and value lists sometimes continue on the next page (for example, delinquency status on pp.10–11).
- The current User Guide notes that, for periods on or before September 2025, `00` could also mean a cycle before the first payment date (p.10). The warehouse treats `00` as not 60+ delinquent in either case, so the 60+ flag is unaffected.
