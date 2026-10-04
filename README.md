# Mortgage Loan Performance Data Platform

This project builds an end-to-end data platform from Freddie Mac loan-level data. It is designed to ingest quarterly releases, detect and handle corrections to previously published history, build an Oracle warehouse, and produce quality-checked analysis results traceable to source files. This version, Milestone 2, contains the raw-archive checksum tool, Oracle ODS tables and loader, and the completed loan-review database design; the remaining components are shown below.

## What the platform does

| Component | What it does | Status |
|---|---|---|
| Raw archive | Records SHA-256 checksums in a manifest and verifies downloaded archives when the user runs the verification command; loading does not run this check automatically. | Done |
| ODS layer | Loads origination and monthly files as text into four layout-specific Oracle tables, records release and source file, and replaces a file's partition through a checked staging table. | Done |
| Release diff and targeted backfill | Compares releases to find revised history and recomputes affected downstream results. | Planned |
| Data warehouse | Organizes loan-level history and dimensions for analysis in Oracle. | Planned |
| Data quality and lineage | Checks downstream data and traces analysis results through processing steps to source files; ODS loading already checks row counts and content fingerprints. | Planned |
| Large-scale processing | Uses Spark for larger volumes if benchmarks show it is needed. | Planned |
| Loan-review application | The completed 13-table, third-normal-form OLTP design describes an Analyst/Manager review workflow, a Spring Boot interface, and timestamp-based CDC into the warehouse; implementation is scheduled for later milestones. | Design done |
| Dashboards | Presents the analysis in Tableau. | Planned |

## What this version can run

You can create or verify an archive manifest, inspect a downloaded sample, deploy the ODS objects, load one year's origination and monthly files, and run the database-backed ODS tests. The loan-review system is a completed design and ER diagram in `docs/oltp_design.md`; this version contains no runnable OLTP tables, web application, warehouse transformations, analysis results, Spark jobs, or dashboards.

## Questions it answers

Later milestones will produce results for three questions:

1. How do loans move between delinquency states, including cures and repeat delinquency?
2. What outcomes follow a payment modification?
3. How does performance differ by origination year (vintage)?

This version prepares the source and ODS data; it does not calculate those answers.

## Status

The repository is updated at each milestone and contains only the completed portions released so far. The schedule below records project status as of October 3, 2026; planned dates may change.

| # | Milestone | Main deliverables | Target date | Status |
|---|---|---|---|---|
| 1 | Project Proposal | Project scope and plan. | 09/19/2026 | Done |
| 2 | Environment, Source Data, and OLTP Design | Oracle in Docker; source manifest and profiling; loaded ODS; completed conceptual, logical, and relational OLTP models in 3NF. | 10/03/2026 | Done |
| 3 | Thin End-to-End Path | One vintage through a first warehouse fact, one metric, one Tableau chart, and one review page; OLTP models in Data Modeler, generated DDL, and core tables. | 10/17/2026 | In progress |
| 4 | Thicken the Databases and ETL | Full OLTP objects and tests; warehouse star schema, ETL, quality checks, reconciliation, and three analyses. | 10/31/2026 | Planned |
| 5 | Thicken the Application and Change Processing | Analyst/Manager pages, access controls, timestamp CDC, release diff, targeted backfill, and lineage. | 11/14/2026 | Planned |
| 6 | Dashboards, Spark scale-up, and end-to-end testing | Tableau dashboards, benchmark-guided Spark processing, and end-to-end tests; stretch: full-history Spark processing on a multi-node cluster. | 11/28/2026 | Planned |
| 7 | Documentation and end-to-end demo | Documentation, demonstration, and rehearsal. | 12/06/2026 | Planned |

## Design notes

- The ODS stores source fields as text and adds `release_id` and `source_file`. Oracle stores empty strings as `NULL`, so this is not byte-for-byte preservation. Primary keys include `release_id`; versions of the same loan from different releases can coexist for later comparison.
- Tables follow file layout, not release number: R45/R46 use the earlier layout tables and R47 uses the newer layout tables. A new release with the same layout reuses its layout's tables.
- Reloading a file fills a staging table first, checks its row count and content fingerprint, and then exchanges the matching partition. The published partition is replaced as one operation rather than left half loaded.

## Source data

The [Freddie Mac Single-Family Loan-Level Dataset page](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset) provides a sample archive for each origination year. A full vintage year has a random sample of 50,000 loans; a partial year has fewer. Each archive has one origination file and one monthly performance file, both pipe-delimited. A vintage is the year a loan originated. Older vintages usually have more months of observed performance. You need one sample year for the ODS walkthrough; the database tests use their own small fixtures and require no downloaded data.

Download one sample archive (`sample_YYYY.zip`) and note its **actual filename**, origination year, and release. The July 2026 and later layout uses `sample_orig_YYYY.txt` and `sample_perf_YYYY.txt`; the earlier layout uses `sample_orig_YYYY.txt` and `sample_svcg_YYYY.txt`. Check the names inside your ZIP before choosing the ODS tables. If you use the newer layout and want to run the optional profiler, also download its matching File Headers; the older layout has no official header files for that script. The File Layout and User Guide on the data page explain the columns and codes. The full dataset is not needed here. Source data is not distributed in this repository.

The provided manifest records six archives used in this project, including earlier releases. It is **not** a checklist of required downloads. For a different archive or year, make your own manifest as shown below. A checksum from `docs/raw_manifest.csv` applies only to the exact file listed there; renaming another download does not make it the same file. A release ID such as `R47` is a label you supply to the loader and use consistently for that download.

## Repository layout

```text
scripts/       Start an existing Oracle container, create a database user, deploy ODS, run SQL
python/        Database connection, raw-file manifest, optional sample profiler, ODS loader
source/ods/    Four ODS tables, staging tables, partition-exchange procedure, statistics
checks/        ODS content fingerprint function; post-deployment invalid-object check
test/          Database-backed loader tests
docs/          Example raw manifest, completed OLTP design and ER diagram
```

## Setup and load one sample

Run these commands from the repository root in a bash shell. This walkthrough assumes Docker, Python 3.11, and macOS, Linux, or Windows with WSL 2. It was tested on macOS; the other platforms have not been verified. You need enough free disk space for the Oracle database image and files you download.

1. Start a new Oracle Database Free container, then wait for its health check. If you already created `oracle-db`, skip `docker run` and use the waiting script. The container uses a persistent Docker volume named `oracle-data`.

   ```bash
   docker run -d --name oracle-db -p 1521:1521 -e ENABLE_ARCHIVELOG=false -e ENABLE_FORCE_LOGGING=false -v oracle-data:/opt/oracle/oradata container-registry.oracle.com/database/free:latest
   scripts/0_start_db.sh
   ```

2. Create the `loan_dw` schema once. The creation script asks you to set a database password. After creating the Python environment in step 3, run `.venv/bin/python python/password_store.py set loan_dw` to save that same password to `~/.config/loan-dw/passwords.json`. Later commands read the password only from this private file and stop with a clear error if its account entry is missing. The file is outside the repository; its directory must be accessible only to you (`700`) and the file must be `600`. It is readable as plain text after login, so use full-disk encryption on your computer if you need protection while it is powered off. The scripts do not access the macOS Keychain.

   ```bash
   scripts/1_create_db_user.sh loan_dw
   ```

3. Create the Python environment and the four ODS tables, staging tables, fingerprint function, and exchange procedure. Deploy once to a new schema.

   ```bash
   python3.11 -m venv .venv
   .venv/bin/python -m pip install -r requirements.txt
   .venv/bin/python python/password_store.py set loan_dw
   scripts/2_create_ods.sh
   ```

4. Put your ZIP in `../data/raw/<release>/` (outside this repository). In the example below, replace `YEAR`, `RELEASE`, and `ARCHIVE` with your year, your release label, and the archive's actual filename. Run the assignments and commands in the same shell. The example values describe one archive; they are not required filenames or a required vintage.

   ```bash
   YEAR=2023
   RELEASE=R47
   ARCHIVE=sample_2023.zip
   RAW_DIR="../data/raw/$RELEASE"
   mkdir -p "$RAW_DIR"
   # Copy the downloaded ZIP to "$RAW_DIR/$ARCHIVE" using your file manager.
   .venv/bin/python python/raw_manifest.py build "$RAW_DIR" ../data/my_manifest.csv
   .venv/bin/python python/raw_manifest.py verify "$RAW_DIR" ../data/my_manifest.csv
   ```

   `build` records every non-hidden file in `$RAW_DIR`; `verify` must finish with “All N files in the manifest match” before loading. Keep the manifest outside that directory so it cannot list itself. To verify the exact project archives listed in `docs/raw_manifest.csv`, instead use `../data/raw` as the raw directory and that CSV as the manifest; missing listed archives make verification fail.

5. Inspect and extract the archive with Python's standard library. Choose the table names from the two filenames shown by the listing, not from the origination year. The example commands below assume the July 2026 or later layout.

   ```bash
   EXTRACT_DIR="../data/extracted/$RELEASE/sample_$YEAR"
   .venv/bin/python -m zipfile -l "$RAW_DIR/$ARCHIVE"
   mkdir -p "$EXTRACT_DIR"
   .venv/bin/python -m zipfile -e "$RAW_DIR/$ARCHIVE" "$EXTRACT_DIR"
   ```

6. Optionally profile a newer-layout sample before loading. Put its two matching official header text files in a directory of your choice and give their actual paths. The profiler prints counts and unmatched-loan counts; inspect those counts yourself. It does not fail merely because the origination and performance loan sets differ. Skip this step for an older-layout archive or if you did not download the File Headers.

   ```bash
   .venv/bin/python python/profile_sample.py "$EXTRACT_DIR/sample_orig_$YEAR.txt" /path/to/origination_data_file_header.txt "$EXTRACT_DIR/sample_perf_$YEAR.txt" /path/to/performance_data_file_header.txt
   ```

7. Load both files, then gather Oracle optimizer statistics. For the earlier layout, change `ods_orig` to `ods_orig_pre202607`, change `ods_perf` to `ods_perf_pre202607`, and load `sample_svcg_YYYY.txt` as the performance file. The `RELEASE` label must match the archive you extracted. Rerunning a successful load for the same release and filename replaces that file's partition.

   ```bash
   .venv/bin/python python/load_ods.py "$RELEASE" ods_orig "$EXTRACT_DIR/sample_orig_$YEAR.txt"
   .venv/bin/python python/load_ods.py "$RELEASE" ods_perf "$EXTRACT_DIR/sample_perf_$YEAR.txt"
   scripts/run_sql.sh source/ods/gather_ods_stats.sql
   ```

The loader checks the number of rows in its staging table and compares fingerprints before and after partition exchange. These are database-side checks; the raw ZIP's SHA-256 check is the separate manifest step. Oracle stores empty strings as `NULL`, so “raw text” does not mean byte-for-byte preservation of the source file.

## Tests

After the ODS objects exist, run the database-backed tests with the same database user and password source used above:

```bash
.venv/bin/python -m unittest discover -s test -p "test_*.py"
```

The tests create and drop small temporary tables, exercise bad inputs and reloads, and do not need Freddie Mac data. They require a working Oracle connection and the deployed `ods_file_hash` function and `ods_exchange_file` procedure.
