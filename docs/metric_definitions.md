# Metric definitions

These definitions describe the warehouse metric in this release. Page numbers refer to Freddie Mac's *Single-Family Loan-Level Dataset General User Guide*, Release 47, July 2026. “Project convention” means the source defines the field but does not prescribe this project's calculation.

## 1. Delinquency of 60 days or more (DLQ60+)

A loan is 60+ delinquent in a month according to its Current Loan Delinquency Status:

| Value | Counts as 60+? | Basis |
|---|---|---|
| Numeric `02` or higher | Yes | User Guide p.10: `02` means 60–89 days, `03` means 90–119 days, and the numeric scale continues up to `99`. |
| `00` or `01` | No | User Guide p.10: `00` is current or less than 30 days delinquent; `01` is 30–59 days. |
| `RA` | Yes | User Guide p.10 defines REO acquisition. Counting it as 60+ is a project convention. |
| `XX` | No | User Guide p.10 defines unavailable status. Treating it as unknown rather than delinquent is a project convention. |

The classification is stored once in `dim_delinquency_status.is_dlq60`. The monthly fact references this dimension, and the loan summary reads the flag from it.

## 2. Months on book (MOB)

`MOB = months_between(reporting month, first payment date) + 1`.

The User Guide p.10 gives this calculation for an unmodified loan's Loan Age. For a modified loan, the official Loan Age uses the modified first payment date and therefore resets. This project consistently uses the original first payment date for the vintage curve, including modified loans. That consistent choice is a project convention.

## 3. Origination vintage

The loan identifier has the form `PYYQnXXXXXXX`; `YYQn` identifies the origination year and quarter (User Guide p.7). The dataset begins in 1999 (p.16), so `99` maps to 1999 and other two-digit years map to `20YY` for the covered data.

## 4. Cumulative 60+ delinquency rate by origination quarter and MOB

For origination quarter `q` and month `m`, the rate is `cum_dlq60_loans / eligible_loans`:

- **Group:** Origination year and quarter encoded in the loan identifier (User Guide p.7). To report a year, sum the four quarters' numerators and denominators separately, then divide; do not average four rates.
- **Denominator (`eligible_loans`):** Loans in the quarter whose original first payment month is early enough to reach MOB `m` by the release's last observed reporting month. A loan that pays off later remains in the denominator for months it could have reached.
- **Numerator (`cum_dlq60_loans`):** Eligible loans whose first observed 60+ month has MOB at or before `m`. A loan enters once, even if it cures and later becomes delinquent again.
- **Cutoff:** The latest monthly reporting period observed in the release. For the project's R47 sample this is March 2026.

The rate, denominator, first-event treatment, and cutoff rule are project conventions. Results are stored in `ads_vintage_dlq60_curve`, one row per release, origination quarter, and MOB.

The observable denominator avoids counting younger loans that could not yet contribute an event at later MOBs. The earlier all-loans denominator understated later-month rates for recent vintages. At the end of a quarter's curve, the remaining eligible loans may still differ from the original group. For a chart, this project includes points only while `eligible_loans >= 0.95 * cohort_loans`; the ADS table retains all calculated months. The 95% display threshold is a project convention. The Tableau chart that applies this threshold is `img/dlq60_curve.png`.

### Why the denominator changed on September 25, 2026

The earlier denominator was every loan in the origination year. That is adequate for an older vintage such as 2010, but understates the rate for younger vintages: a loan originated in the second half of 2025 could not yet reach month 12 by the cutoff, so it could not contribute to the numerator while it was still counted in the denominator. For the 2025 vintage at month 12, the earlier result was 0.36% (182 / 50,000), while the revised observable-loan result was 0.69% (52 / 7,536). This revision is a project convention.

### Why the curve groups by quarter and displays points only above 95% coverage

With an observable denominator, the tail of a yearly curve can change composition: only loans originated earlier in the year remain eligible. Those loans may have different performance from loans originated later. The project measured these rates for a 2010 sample:

| First payment quarter | Loans | Share ever reaching 60+ |
|---|---:|---:|
| 2010Q1 | 4,384 | 4.77% |
| 2010Q2 | 12,273 | 5.36% |
| 2010Q3 | 11,661 | 4.22% |
| 2010Q4 | 13,372 | 3.56% |
| 2011Q1 | 8,285 | 3.81% |

After month 184, a yearly view retained only loans from the first two quarters; its rate jumped from 4.3% to 5.2% and later fell. That jump reflects a changing group, not necessarily more delinquency. Grouping by origination quarter makes the group more consistent. For display, keep only months where the denominator remains at least 95% of the quarter's original loans; the ADS table retains every month. This display threshold is a project convention.

Aggregating the quarterly numerators and denominators by year gives the same annual figures as the earlier annual grouping; for example, month 12 of the 2010 vintage is still 177 / 50,000. In the project sample, each origination quarter contains 12,500 loans.
