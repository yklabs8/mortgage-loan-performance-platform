# Mortgage Loan Performance Data Platform

A bank-style loan risk data platform built on Freddie Mac loan-level mortgage data. It turns raw monthly loan files into a layered warehouse and three risk analyses, with data-quality controls and release-aware reprocessing, and feeds a loan-review application where analysts work on loans that turn delinquent.

## Architecture

```text
Freddie Mac archives ──► checksum manifest
        │
        ▼
ODS (raw text, per release) ──► quality gate: stop / quarantine / warn
        │
        ▼
DIM + DWD (monthly facts) ──► DWS (per-loan summaries) ──► ADS (three analyses)
        │                                                      │
        ▼                                                      ▼
review candidates ──► review application (Spring Boot)    Tableau dashboards
```

At full scale the processing runs on HDFS/Hive and Spark, and Oracle serves the delivered results and the review application. This repository publishes the Oracle sample warehouse, which is the development and regression reference for the same logic.

## Components

| Component | What it does | Status |
|---|---|---|
| Raw archive | SHA-256 manifest; downloaded archives are verified with a manual command before loading. | Done |
| ODS layer | Loads origination and monthly files as text, tagged with release and source file; a reload replaces one file's partition as a single step. | Done |
| Analytical star schema | Date, geography, servicer, loan, and code dimensions; release-partitioned monthly facts; per-loan summaries; eight analysis tables. | Done |
| Data quality | Rule results and offending rows are recorded; HARD failures stop the load, invalid loan references and months can be quarantined, warnings are kept. | Done |
| Release diff and targeted backfill | Compares two releases, finds loans whose history changed, copies unchanged loan summaries, and recomputes only the changed loans. | Done |
| Data models | Data Modeler enterprise, logical, and relational models with generated DDL (`docs/model/`). | Done |
| Review candidates and page | Rule-based candidate selection from the warehouse and a read-only Spring Boot candidate page. | Done |
| Full review workflow and CDC | Analyst/Manager workflow and timestamp-based CDC back to the warehouse; the design is in `docs/oltp_design.md`. | Design done |
| Large-scale processing | Spark/Hive pipeline, batch delivery to Oracle, and scheduling. | Design done |
| Dashboards — first chart | Cumulative 60+ curve by origination quarter (below). | Done |
| Dashboards — full set | Tableau dashboards for all three analyses. | Planned |

Components marked Done are in this repository. Those marked Design done are implemented in the wider project and not published here yet.

## Analyses

1. **Delinquency roll rates**: how loans move between delinquency states month to month, including cures and repeat delinquency.
2. **Vintage curves**: cumulative 60+ day delinquency by origination quarter and months on book.
3. **Payment modifications**: outcomes in the 12 months after a loan's first modification.

Each analysis is also split by nine loan attributes such as credit score and loan-to-value. Rates are computed from summed counts, never by averaging subgroup rates. A separate Python script recomputes every result from the raw files, and the cells match. Definitions are in `docs/metric_definitions.md`.

## Engineering highlights

- **Reloads are all-or-nothing.** A file is loaded into a staging table, its row count and content fingerprint are checked, and then it replaces the live partition in one step, so readers never see a half-loaded file.
- **Corrections recompute only what changed.** Freddie Mac reissues the full history in each release, so a new release is loaded in full and kept beside the previous one. The two are compared loan by loan; summaries of unchanged loans are copied, and only loans whose history changed are recomputed.
- **Quality gate before loading.** Every rule result and offending row is recorded. Problems that make a whole file suspect, such as an empty file, duplicate keys, or an unknown status code, stop the load. Defects confined to one row, such as a monthly record for an unknown loan or an invalid month, are quarantined and the rest is loaded. The warehouse load refuses a quality check older than the latest source load.
- **Least privilege.** The web page account can only read three tables; it cannot write or run procedures.

## Data models

Review application (OLTP):

![OLTP relational model](docs/model/oltp_relational.png)

Warehouse:

![Warehouse relational model](docs/model/dw_relational.png)

Cumulative 60+ delinquency by origination quarter (Tableau):

![Cumulative 60+ curve](docs/img/dlq60_curve.png)

## Status

Updated at each milestone. As of October 29, 2026, Milestones 1–4 are Done and Milestones 5–6 are In progress. Milestone status covers the whole project, including work not yet published here.

| # | Milestone | Main deliverables | Target date | Status |
|---|---|---|---|---|
| 1 | Project Proposal | Proposal submitted | 09/19/2026 | Done |
| 2 | Environment, Source Data, and OLTP Design | Oracle in Docker; source data with checksum manifest; data profiling; ODS loaded; OLTP conceptual, logical, and relational design (3NF) | 10/03/2026 | Done |
| 3 | Thin End-to-End Path | One vintage through every layer: ODS → first fact table with DIM_DATE → one delinquency metric → one Tableau chart; OLTP models in Data Modeler, DDL, core tables; review candidates from the warehouse shown on one web page (Data Modeler models and DDL moved to Milestone 4) | 10/17/2026 | Done |
| 4 | Thicken the Databases and ETL | OLTP: all tables, indexes, triggers, functions, procedures, sample data, constraint and trigger tests, rule-mapping additions, Data Modeler models and DDL. Warehouse: full star schema with DIM_DATE, Enterprise / Logical / Relational models and DDL; ETL with external tables and PL/SQL; data quality rules and reconciliation; all three analyses | 10/31/2026 | Done |
| 5 | Thicken the Application and Change Processing | Analyst and Manager pages with menus; role-based grants and password management; validation, confirmations, SQL-injection and XSS protection; timestamp-based CDC from OLTP to the warehouse; release-diff and targeted backfill test case; lineage | 11/14/2026 | In progress |
| 6 | Reports, Scale-up, and Testing | Core: Tableau dashboards for roll-rate, vintage, and payment-modification analysis; Phase 2 Spark scale-up on multiple vintages with benchmark; end-to-end tests. Stretch (only if earlier milestones finish early): full-history Spark run on a multi-node cluster; additional-source comparison | 11/28/2026 | In progress |
| 7 | Final Deliverables | Final project report; presentation; demo rehearsal and recording | 12/06/2026 | Planned |

## Repository layout

```text
scripts/       Oracle setup, ODS deployment, warehouse loads, external-table loading
python/        Database access, archive checks, loaders, independent raw-file reconciliation
source/ods/    Four source tables, stages, exchange procedure, load-event ledger, external tables
source/dim/    Date, loan, durable keys, geography, servicer, status/code dimensions, segment view
source/dwd/    Partitioned monthly fact, exchange stage, release loading, targeted recomputation
source/dws/    Per-loan performance and modification summaries
source/ads/    Three analyses, five segmented outputs, release-difference tables and procedures
source/rpt/    Read-only views for the three core analyses
source/oltp/   Core review tables, candidate rule, and candidate procedure
source/ops/    Grants for the page account
app/           Read-only candidate page (Spring Boot)
checks/        Source/detail quality, issue/quarantine records, freshness gate, object checks
test/          Database-backed source-loader tests
docs/          Setup steps, metric definitions, source-field map, review design, manifest, images
docs/model/    Data Modeler enterprise, logical, and relational diagrams and model-generated DDL
```

## Run it locally

You need Docker, Python 3.11, and one free sample year from the [Freddie Mac Single-Family Loan-Level Dataset](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset). Step-by-step commands and tests are in `docs/setup.md`; this version was deployed from an empty database schema with those steps.
