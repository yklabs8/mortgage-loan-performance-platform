# Mortgage Loan Performance Data Platform

This milestone contains a raw-file checksum tool, Oracle operational data store (ODS) tables and loader, and a proposed loan-review system design. It does not yet build the downstream warehouse, analysis results, web application, or dashboards.

## Scope of this version

| Component | Available now |
|---|---|
| Raw archive manifest | Build a SHA-256 manifest for your own downloads, then verify the listed files on demand. A manifest for the files used in this project is included as `docs/raw_manifest.csv`. |
| ODS | Four tables cover the origination and monthly performance files in the current and pre-July-2026 layouts. The loader records a release ID and source filename and replaces one file's partition through a staging table. |
| OLTP | A 13-table design and ER diagram in `docs/oltp_design.md`; no OLTP deployment scripts are included yet. |

Release comparison, warehouse transformations, data-quality rules beyond loader checks, analysis metrics, Spark processing, the review application, and dashboards are planned for later milestones. The intended analysis questions are delinquency transitions (including cures and repeat delinquency), outcomes after payment modification, and differences by origination year (vintage). No command in this version calculates those metrics.

## Source data

The [Freddie Mac Single-Family Loan-Level Dataset page](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset) provides a sample archive for each origination year. A full vintage year has a random sample of 50,000 loans; a partial year has fewer. Each archive has one origination file and one monthly performance file, both pipe-delimited. A vintage is the year a loan originated. Older vintages usually have more months of observed performance. You need one sample year for the ODS walkthrough; the database tests use their own small fixtures and require no downloaded data.

Download one sample archive (`sample_YYYY.zip`) and note its **actual filename**, origination year, and release. The July 2026 and later layout uses `sample_orig_YYYY.txt` and `sample_perf_YYYY.txt`; the earlier layout uses `sample_orig_YYYY.txt` and `sample_svcg_YYYY.txt`. Check the names inside your ZIP before choosing the ODS tables. If you use the newer layout and want to run the optional profiler, also download its matching File Headers; the older layout has no official header files for that script. The File Layout and User Guide on the data page explain the columns and codes. The full dataset is not needed here. Source data is not distributed in this repository.

The provided manifest records six archives used in this project, including earlier releases. It is **not** a checklist of required downloads. For a different archive or year, make your own manifest as shown below. A checksum from `docs/raw_manifest.csv` applies only to the exact file listed there; renaming another download does not make it the same file. A release ID such as `R47` is a label you supply to the loader and use consistently for that download.

## Repository layout

```text
scripts/       Start an existing Oracle container, create a database user, deploy ODS, run SQL
python/        Database connection, raw-file manifest, optional sample profiler, ODS loader
source/ods/    Four ODS tables, staging tables, partition-exchange procedure, statistics
checks/        ODS content fingerprint function
test/          Database-backed loader tests
docs/          Example raw manifest, proposed OLTP design and ER diagram
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
