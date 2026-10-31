# Metric definitions

These definitions describe the warehouse metric in this release. Page numbers refer to Freddie Mac's *Single-Family Loan-Level Dataset General User Guide*, Release 47, July 2026. “Internal analysis definition” means the source defines the field but does not prescribe this calculation; the definition is the platform's own, not an official rule.

## 1. Delinquency of 60 days or more (DLQ60+)

A loan is 60+ delinquent in a month according to its Current Loan Delinquency Status:

| Value | Counts as 60+? | Basis |
|---|---|---|
| Numeric `02` or higher | Yes | User Guide p.10: `02` means 60–89 days, `03` means 90–119 days, and the numeric scale continues up to `99`. |
| `00` or `01` | No | User Guide p.10: `00` is current or less than 30 days delinquent; `01` is 30–59 days. |
| `RA` | Yes | User Guide p.10 defines REO acquisition. Counting it as 60+ is an internal analysis definition. |
| `XX` | No | User Guide p.10 defines unavailable status. Treating it as unknown rather than delinquent is an internal analysis definition. |

The classification is stored once in `dim_delinquency_status.is_dlq60`. The monthly fact references this dimension, and the loan summary reads the flag from it.

## 2. Months on book (MOB)

`MOB = months_between(reporting month, first payment date) + 1`.

The User Guide p.10 gives this calculation for an unmodified loan's Loan Age. For a modified loan, the official Loan Age uses the modified first payment date and therefore resets. The warehouse consistently uses the original first payment date for the vintage curve, including modified loans. That consistent choice is an internal analysis definition.

## 3. Origination vintage

The loan identifier has the form `PYYQnXXXXXXX`; `YYQn` identifies the origination year and quarter (User Guide p.7). The dataset begins in 1999 (p.16), so `99` maps to 1999 and other two-digit years map to `20YY` for the covered data.

## 4. Cumulative 60+ delinquency rate by origination quarter and MOB

For origination quarter `q` and month `m`, the rate is `cum_dlq60_loans / eligible_loans`:

- **Group:** Origination year and quarter encoded in the loan identifier (User Guide p.7). To report a year, sum the four quarters' numerators and denominators separately, then divide; do not average four rates.
- **Denominator (`eligible_loans`):** Loans in the quarter whose original first payment month is early enough to reach MOB `m` by the release's last observed reporting month. A loan that pays off later remains in the denominator for months it could have reached.
- **Numerator (`cum_dlq60_loans`):** Eligible loans whose first observed 60+ month has MOB at or before `m`. A loan enters once, even if it cures and later becomes delinquent again.
- **Cutoff:** The latest monthly reporting period observed in the release. For the R47 sample loaded in the warehouse this is March 2026.

The rate, denominator, first-event treatment, and cutoff rule are internal analysis definitions. Results are stored in `ads_vintage_dlq60_curve`, one row per release, origination quarter, and MOB.

The observable denominator avoids counting younger loans that could not yet contribute an event at later MOBs. The earlier all-loans denominator understated later-month rates for recent vintages. At the end of a quarter's curve, the remaining eligible loans may still differ from the original group. For a chart, the platform includes points only while `eligible_loans >= 0.95 * cohort_loans`; the ADS table retains all calculated months. The 95% display threshold is an internal analysis definition. The Tableau chart that applies this threshold is `img/dlq60_curve.png`.

### Why the denominator changed on September 25, 2026

The earlier denominator was every loan in the origination year. That is adequate for an older vintage such as 2010, but understates the rate for younger vintages: a loan originated in the second half of 2025 could not yet reach month 12 by the cutoff, so it could not contribute to the numerator while it was still counted in the denominator. For the 2025 vintage at month 12, the earlier result was 0.36% (182 / 50,000), while the revised observable-loan result was 0.69% (52 / 7,536). This revision is an internal analysis definition.

### Why the curve groups by quarter and displays points only above 95% coverage

With an observable denominator, the tail of a yearly curve can change composition: only loans originated earlier in the year remain eligible. Those loans may have different performance from loans originated later. These rates were measured on a 2010 sample in the warehouse:

| First payment quarter | Loans | Share ever reaching 60+ |
|---|---:|---:|
| 2010Q1 | 4,384 | 4.77% |
| 2010Q2 | 12,273 | 5.36% |
| 2010Q3 | 11,661 | 4.22% |
| 2010Q4 | 13,372 | 3.56% |
| 2011Q1 | 8,285 | 3.81% |

After month 184, a yearly view retained only loans from the first two quarters; its rate jumped from 4.3% to 5.2% and later fell. That jump reflects a changing group, not necessarily more delinquency. Grouping by origination quarter makes the group more consistent. For display, keep only months where the denominator remains at least 95% of the quarter's original loans; the ADS table retains every month. This display threshold is an internal analysis definition.

Aggregating the quarterly numerators and denominators by year gives the same annual figures as the earlier annual grouping; for example, month 12 of the 2010 vintage is still 177 / 50,000. In the warehouse sample, each origination quarter contains 12,500 loans.

## 5. Delinquency transitions (roll rates)

`ads_dlq_transition_monthly` stores counts by release, origination year, destination month, prior state, and current state. A roll rate is a cell count divided by the total count for the same prior state. Sum counts before dividing; do not average rates.

| State | Current Loan Delinquency Status |
|---|---|
| C (current or under 30 days) | `00` |
| 30 | `01` |
| 60 | `02` |
| 90 | `03` |
| 120+ | `04`–`99` |
| REO | `RA` |
| UNK | `XX` |

The source codes are defined in User Guide p.10; the grouping is an internal analysis definition. Include a transition only when two observed records are exactly one calendar month apart. First observations and gaps do not contribute a transition.

An exit in the destination month overrides its delinquency state. Source meanings are in User Guide p.11; the categories below are internal analysis definitions.

| Exit state | Zero Balance Code |
|---|---|
| PREPAID | `01` (prepaid or matured) |
| LIQUIDATED | `02`, `03`, `09` (third-party sale, short sale/charge-off, or REO disposition) |
| LOAN_SALE | `15`, `16` |
| DEFECT | `96` (confirmed underwriting or servicing defect) |

These exit codes occur in the final reporting month (User Guide p.16). LIQUIDATED includes several disposition types and must not be described as exclusively foreclosure. `python/reconcile_transition.py` recomputes states and every transition cell directly from raw monthly files without reading the code dimensions.

## 6. Outcomes after first modification

Modification Flag `Y` means modified this month, `P` means previously modified, and an empty value means no modification (User Guide p.11; Disclosure Changes p.4). A loan may have multiple `Y` months. This analysis uses its first `Y` month.

`dws_mod_loan_td` holds one row per modified loan and release. Prior status records whether any 60+ observation occurred in months -12 through -1; no prior records is a separate group. Checking only month -1 can miss distress because reported delinquency may reset before the modification flag appears.

Redefault means a 60+ observation in months 1–12 after modification, excluding the modification month itself. Month-12 status uses the delinquency state at that month, or the exit state if the loan exited earlier. Loans not yet observable through month 12 and without an earlier exit have a NULL status. Only observable loans enter either the numerator or denominator of the rates.

`ads_modification_outcome` groups by origination year, first modification year, and prior 60+ status. It records modified/observable/redefault/current/prepaid counts. Redefault and current rates divide by observable loans and are NULL for a zero denominator. Window choices and grouping are internal analysis definitions. `python/reconcile_modification.py` independently recomputes every modified-loan summary from raw monthly records.

## 8. Analytical scope

The source dataset represents its disclosed eligible mortgage population, not all mortgages or all borrowers. Results must be interpreted within that scope. The retained `comparable_flag` identifies a narrower population and does not automatically filter all analytical outputs. For Freddie records it excludes HARP, known original LTV above 97, prepayment penalties, and original terms below 60 or at least 420 months. This flag is separate from the FICO/LTV bands and is not an official risk rating.

## 9. Loan-attribute segments

Use each release's own origination attributes, including corrections in that release. Band boundaries are internal analysis definitions, not official credit-risk grades. Virtual dimension columns compute bands from raw values.

| Attribute | Mutually exclusive bands | Unavailable |
|---|---|---|
| FICO | `<620`, `[620,680)`, `[680,740)`, `>=740` | `9999` or NULL becomes UNKNOWN |
| Original LTV | `<=60`, `(60,80]`, `(80,90]`, `(90,97]`, `>97` | `999` or NULL becomes UNKNOWN |

The nine segment types are FICO, LTV, STATE, REGION, CHANNEL, LOAN_PURPOSE, PROPERTY_TYPE, AMORTIZATION, and HARP. Each is grouped separately; the nine attributes are never multiplied into a joint cross product. Raw field meanings come from User Guide p.7 and the July 2026 File Layout. Census regions come from `state-geocodes-v2023.xlsx`; territories retain `Not in a Census region`. Missing attribute codes use UNKNOWN, including missing HARP rather than treating it as N. LTV is not a cash down-payment measure.

For every segment type, group count totals must equal the corresponding unsegmented result. Recalculate rates within each group. Segmented vintage curves preserve a row even when the group has no eligible loans at a late MOB: fixed cohort count, zero eligible/60+ counts, and NULL rate. NULL means no denominator, not zero risk.

Final outcome uses the last exit code through the release, or ACTIVE if no exit. Each loan contributes once. This is a different grain from monthly transition events.

### 9.1 Cure and relapse

After a 60+ observation, three consecutive calendar months in `00` with no exit code form a cure at the third current month. Missing months, `01`, `XX`, 60+, and exits break the streak. A later 60+ observation is a relapse. Another cure can be counted after a new 60+ episode, but an uninterrupted current streak produces only one cure. These are internal analysis definitions; source status meanings are in User Guide p.10.

`ads_cure_redefault_segment` stores distinct loans ever 60+, distinct cured loans, cure events, and distinct loans with a post-cure relapse. Cure events may exceed distinct cured loans. `cure_rate = cured_loans / dlq60_loans`, NULL when the denominator is zero. A separate relapse-rate denominator is not defined here. `python/reconcile_segment.py` independently checks the segmented outputs, including cure events, from raw files and Census references.
