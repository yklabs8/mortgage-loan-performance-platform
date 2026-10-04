# Mortgage Loan Performance Data Platform

An end-to-end data engineering platform on real mortgage loan-level data (Freddie Mac Single-Family Loan-Level Dataset). It ingests Freddie's quarterly releases, detects and handles Freddie's revisions to already-published history, builds an Oracle data warehouse, and produces analysis-ready results that are checked for data quality and traceable to the exact source files.

## What the platform does

| Component | What it does | Status |
|---|---|---|
| Raw archive | Every source archive recorded with its release and SHA-256 checksum; verified before every load | Done |
| ODS layer | Every field stored exactly as received, tagged with its release; one table per Freddie file layout; reloads go through a staging table and partition exchange, so a table is never half-loaded | Done |
| Release diff and targeted backfill | Compare two releases loan by loan, find the history Freddie revised, and recompute only the affected loans | Planned |
| Data warehouse | Star schema with DIM_DATE; batch ETL with Oracle external tables and PL/SQL | Planned |
| Data quality and lineage | Rules at every layer, cross-layer reconciliation, and every result traceable to its release and source file | Planned |
| Large-scale processing | Spark recomputation over many vintages, with the need for Spark shown by benchmark | Planned |
| Loan-review application | Normalized Oracle OLTP schema (13 tables, 3NF) with a Java Spring Boot app for Analyst and Manager roles; timestamp-based CDC into the warehouse | Design done; build planned |
| Dashboards | Tableau dashboards on the warehouse | Planned |

## Questions it answers

1. **Delinquency transition (roll rate):** how loans move between current and 30/60/90+ days delinquent, including cure and re-default.
2. **Payment-modification outcomes:** whether loans improve or re-default after a modification.
3. **Vintage analysis:** whether performance differs by origination year.

## Status

This repository is updated at each milestone. Only completed milestones are included.

| # | Milestone | Target date | Status |
|---|---|---|---|
| 1 | Project proposal | 09/19/2026 | Done |
| 2 | Environment, source data, ODS, and OLTP design | 10/03/2026 | **Done (this version)** |
| 3 | Thin end-to-end path: one vintage from ODS to a first fact table, one metric, one Tableau chart; core OLTP tables; review candidates on one web page | 10/17/2026 | Planned |
| 4 | Thicken the databases and ETL | 10/31/2026 | Planned |
| 5 | Thicken the application and change processing (CDC, release diff, backfill) | 11/14/2026 | Planned |
| 6 | Dashboards, Spark scale-up, and end-to-end testing (stretch, if earlier milestones finish early: full-history Spark run on a multi-node cluster; Fannie Mae as a second source) | 11/28/2026 | Planned |
| 7 | Documentation and end-to-end demo | 12/06/2026 | Planned |

## Source data

For each origination year (vintage), Freddie Mac publishes two pipe-delimited files:

- **Origination file:** one row per loan (credit score, loan-to-value, debt-to-income, interest rate, state, ...).
- **Monthly performance file:** one row per loan per month (unpaid balance, delinquency status, modification flag, termination code, losses, ...).

Freddie republishes the whole dataset about every quarter as a new release (R45, R46, R47, ...), and a release can correct history that was already published. The official sample is a random 50,000 loans per vintage with the same fields as the full dataset.

**The data is not included in this repository** (Freddie Mac's terms do not allow redistribution).

### What to download

From the [Freddie Mac Single-Family Loan-Level Dataset page](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset) (free registration; you must accept Freddie Mac's terms of use), download:

| What | File | Used for |
|---|---|---|
| Sample dataset, origination years 2010, 2023, 2025 | `sample_2010.zip`, `sample_2023.zip`, `sample_2025.zip` (each holds `sample_orig_YYYY.txt` and `sample_perf_YYYY.txt`) | Development and all steps in this version |
| File Layout, File Headers, User Guide | documentation files on the same page; File Headers holds `origination_data_file_header.txt` and `performance_data_file_header.txt` | Column definitions; the headers are needed by `profile_sample.py` |
| Full standard dataset (optional, large: about 40 GB compressed per release) | one archive with every quarter from 1999 on | Later large-scale (Spark) milestones only |

Place the archives under `../data/raw/<release>/`, named as listed in `docs/raw_manifest.csv` (for example `../data/raw/R47/R47_sample_2010.zip`), so that `raw_manifest.py verify` can find them.

**About releases:** the site offers only the current release (R47 at the time of writing). Earlier releases, needed for the release-diff test case, are not regular downloads; `docs/raw_manifest.csv` lists the R45 and R46 archives this project used, with their SHA-256 checksums, so a copy can be verified. Checksums of the current release match only while Freddie has not published a newer one.

## Repository layout

```
scripts/       0_start_db.sh, 1_create_db_user.sh, 2_create_ods.sh, run_sql.sh
python/        db.py (connection), raw_manifest.py (checksums), profile_sample.py (profiling), load_ods.py (loader)
source/ods/    ODS tables (two Freddie file layouts), exchange staging tables, partition-exchange procedure
checks/        ods_file_hash.sql (per-file content fingerprint)
test/          loader tests
docs/          raw_manifest.csv, oltp_design.md (OLTP design: business basis, ER model, rationale, limitations)
```

## Design notes

- **ODS stores every field exactly as received** (as text, no conversion), plus `release_id` and `source_file`. The primary key includes `release_id`, so several releases of the same loan can be stored side by side and compared later.
- **One ODS table per file layout, not per release.** R45 and R46 use Freddie's pre-July-2026 layout; R47 uses the new layout (renamed columns, sign changes, new fields), so it has its own tables.
- **Reloads never leave a half-loaded table.** A file is loaded into a staging table, checked (row count and content fingerprint), and then swapped into its partition with `ALTER TABLE ... EXCHANGE PARTITION`.

## Setup

Requires Docker, Python 3.11, and a bash shell: macOS, Linux, or Windows with WSL 2. Developed and tested on macOS (Apple Silicon); the scripts use only standard bash and Python, but other systems have not been tested.

1. Start Oracle Database Free (official arm64/amd64 image):
   ```bash
   docker run -d --name oracle-db -p 1521:1521 -e ENABLE_ARCHIVELOG=false -e ENABLE_FORCE_LOGGING=false -v oracle-data:/opt/oracle/oradata container-registry.oracle.com/database/free:latest
   ```
   then wait until it is ready: `scripts/0_start_db.sh`
2. Create the project user (you type the password; it is never written to a file): `scripts/1_create_db_user.sh loan_dw`
3. Give the scripts the same password, one of:
   - any system: `export ORACLE_PASSWORD='...'` in the shell where you run the scripts;
   - macOS: store it once in the Keychain with `security add-generic-password -a loan_dw -s loan-dw-oracle -w`;
   - neither: the scripts ask for it each time.
4. Python environment: `python3.11 -m venv .venv && .venv/bin/pip install -r requirements.txt`
5. Create the ODS objects: `scripts/2_create_ods.sh`
6. Put the downloaded archives in `../data/raw/<release>/` (outside the repository) and verify them: `.venv/bin/python python/raw_manifest.py verify ../data/raw docs/raw_manifest.csv`
   The manifest also lists the R45 and R46 archives used for the release comparison. If you only have the current release, `verify` reports those files as missing and exits with an error; that is expected, and every file you do have must still show no size or checksum mismatch.
7. Unzip, for example the 2010 sample of R47:
   ```bash
   mkdir -p ../data/extracted/R47/sample_2010 && unzip ../data/raw/R47/R47_sample_2010.zip -d ../data/extracted/R47/sample_2010
   ```
8. Profile a sample (R47 layout; needs the two File Headers files Freddie publishes with the July 2026 File Layout, `origination_data_file_header.txt` and `performance_data_file_header.txt`): `.venv/bin/python python/profile_sample.py <orig file> <orig header> <perf file> <perf header>`. It prints row and loan counts and checks that every monthly record matches an origination record.
9. Load each file into the ODS table for its layout, then gather statistics:
   ```bash
   .venv/bin/python python/load_ods.py R47 ods_orig ../data/extracted/R47/sample_2010/sample_orig_2010.txt
   ```
   ```bash
   .venv/bin/python python/load_ods.py R47 ods_perf ../data/extracted/R47/sample_2010/sample_perf_2010.txt
   ```
   ```bash
   scripts/run_sql.sh source/ods/gather_ods_stats.sql
   ```
   R45 and R46 use the old layout: load `sample_orig_YYYY.txt` into `ods_orig_pre202607` and `sample_svcg_YYYY.txt` into `ods_perf_pre202607`.

## Tests

```bash
.venv/bin/python -m unittest discover -s test -p "test_*.py"
```

The tests create small temporary tables, check that bad input fails cleanly and that reloads do not duplicate rows, and drop the tables afterwards.

