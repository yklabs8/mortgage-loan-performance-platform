# Setup and load the sample years

Steps 1–9 load the Freddie Mac sample years into the warehouse with a verified source batch and check the results; steps 10–11 select review candidates in Oracle, run the review application, and capture its changes back into the warehouse. The end-to-end test at the end runs all of these steps on an empty database with one script. This version passed it with the 2006, 2007, 2010, and 2015 samples of release R47.

## Source data

The [Freddie Mac Single-Family Loan-Level Dataset page](https://www.freddiemac.com/research/datasets/sf-loanlevel-dataset) provides a sample archive for each origination year. A full vintage year has a random sample of 50,000 loans; a partial year has fewer. Each archive has one origination file and one monthly performance file, both pipe-delimited. A vintage is the year a loan originated. Older vintages usually have more months of observed performance. This version uses four origination years that span the 2008 financial crisis: 2006 and 2007 (originated before it), 2010 (just after it), and 2015. The database tests use their own small fixtures where they can; the candidate selection test and the end-to-end test read the loaded years.

Download the four sample archives (`sample_YYYY.zip`) and note each **actual filename**, origination year, and release. The July 2026 and later layout uses `sample_orig_YYYY.txt` and `sample_perf_YYYY.txt`; the earlier layout uses `sample_orig_YYYY.txt` and `sample_svcg_YYYY.txt`. Check the names inside your ZIP before choosing the ODS tables. If you use the newer layout and want to run the optional profiler, also download its matching File Headers; the older layout has no official header files for that script. The File Layout and User Guide on the data page explain the columns and codes. The full dataset is not needed here. Source data is not distributed in this repository.

The provided manifest records six archives used to build the warehouse, including earlier releases. It is **not** a checklist of required downloads. For a different archive or year, make your own manifest as shown below. A checksum from `docs/raw_manifest.csv` applies only to the exact file listed there; renaming another download does not make it the same file. A release ID such as `R47` is a label you supply to the loader and use consistently for that download.

## Steps

Run these commands from the repository root in a bash shell. You need Docker and Python 3.11; the review application needs Java 17 and Maven.

1. Start a new Oracle Database Free container, then wait for its health check. If you already created `oracle-db`, skip `docker run` and use the waiting script. The container uses a persistent Docker volume named `oracle-data`.

   ```bash
   docker run -d --name oracle-db -p 1521:1521 -e ENABLE_ARCHIVELOG=false -e ENABLE_FORCE_LOGGING=false -v oracle-data:/opt/oracle/oradata container-registry.oracle.com/database/free:latest
   scripts/0_start_db.sh
   ```

2. Create the `loan_dw` schema once. The creation script asks you to set a database password. After creating the Python environment in step 3, run `.venv/bin/python python/password_store.py set loan_dw` to save that same password to `~/.config/loan-dw/passwords.json`. Later commands read it from this file, which stays outside the repository and is readable only by you.

   ```bash
   scripts/1_create_db_user.sh loan_dw
   ```

3. Create the Python environment and deploy the four ODS tables, staging tables, directory grant, external tables, fingerprint function, and external loader. Deploy once to a new schema.

   ```bash
   python3.11 -m venv .venv
   .venv/bin/python -m pip install -r requirements.txt
   .venv/bin/python python/password_store.py set loan_dw
   scripts/2_create_ods.sh
   ```

4. Put your ZIPs in `../data/raw/<release>/` (outside this repository). In the example below, `RELEASE` is your release label and `YEARS` the origination years; each archive is assumed to be named `sample_YEAR.zip`, so adjust the name if yours differs. Run the assignments and commands in the same shell.

   ```bash
   RELEASE=R47
   YEARS="2006 2007 2010 2015"
   RAW_DIR="../data/raw/$RELEASE"
   mkdir -p "$RAW_DIR"
   # Copy the downloaded ZIPs to "$RAW_DIR/" using your file manager.
   .venv/bin/python python/raw_manifest.py build ../data/raw ../data/my_manifest.csv
   .venv/bin/python python/raw_manifest.py verify ../data/raw ../data/my_manifest.csv
   ```

   `build` records every non-hidden file under `../data/raw` with its release folder, which the source-batch check in step 9 uses to find each loaded file's archive; `verify` must finish with “All N files in the manifest match” before loading. Keep the manifest outside that directory so it cannot list itself. To verify the exact archives listed in `docs/raw_manifest.csv`, instead use `../data/raw` as the raw directory and that CSV as the manifest; missing listed archives make verification fail.

5. Inspect and extract each archive with Python's standard library. Choose the table names from the two filenames shown by the listing, not from the origination year. The example commands below assume the July 2026 or later layout.

   ```bash
   for YEAR in $YEARS; do
     EXTRACT_DIR="../data/extracted/$RELEASE/sample_$YEAR"
     .venv/bin/python -m zipfile -l "$RAW_DIR/sample_$YEAR.zip"
     mkdir -p "$EXTRACT_DIR"
     .venv/bin/python -m zipfile -e "$RAW_DIR/sample_$YEAR.zip" "$EXTRACT_DIR"
   done
   ```

6. Optionally profile a newer-layout sample before loading (shown for one year). Put its two matching official header text files in a directory of your choice and give their actual paths. The profiler prints counts and unmatched-loan counts; inspect those counts yourself. Skip this step for an older-layout archive or if you did not download the File Headers.

   ```bash
   YEAR=2010; EXTRACT_DIR="../data/extracted/$RELEASE/sample_$YEAR"
   .venv/bin/python python/profile_sample.py "$EXTRACT_DIR/sample_orig_$YEAR.txt" /path/to/origination_data_file_header.txt "$EXTRACT_DIR/sample_perf_$YEAR.txt" /path/to/performance_data_file_header.txt
   ```

7. Load both files of every year through Oracle external tables, then gather optimizer statistics. Step 3's `scripts/2_create_ods.sh` creates `/opt/oracle/ext_data`, grants the ODS directory, and deploys the external tables and loader. For the earlier layout, use `ods_orig_pre202607`, `ods_perf_pre202607`, and `sample_svcg_YYYY.txt`. The `RELEASE` label must match the extracted archive. A successful rerun replaces only that release and filename's partition.

   ```bash
   for YEAR in $YEARS; do
     EXTRACT_DIR="../data/extracted/$RELEASE/sample_$YEAR"
     scripts/4_load_ods_ext.sh "$RELEASE" ods_orig "$EXTRACT_DIR/sample_orig_$YEAR.txt"
     scripts/4_load_ods_ext.sh "$RELEASE" ods_perf "$EXTRACT_DIR/sample_perf_$YEAR.txt"
   done
   scripts/run_sql.sh source/ods/gather_ods_stats.sql
   ```

   The shell script copies each file into the Oracle container and removes that copy on exit. Oracle validates the file's column and row counts, loads the exchange stage, and compares its fingerprint before and after partition exchange. The old-layout external tables are deployed from the same `source/ods/ext_ods_tables.sql` file.

8. Create the review accounts and every remaining object: dimensions, facts, summaries, analyses, the review (OLTP) database, change data capture, and lineage. Save the three account passwords first. The script deploys each file as its owner in dependency order, marks this database as a TEST environment (the write tests refuse to run anywhere else, so use a development database), grows the USERS tablespace file to 8 GB if smaller (the four sample years fill about half of it), creates the least-privilege web account `loan_app`, and finishes with a SQL test that logs in as that account. Run it once on a new database.

   ```bash
   .venv/bin/python python/password_store.py set loan_oltp
   .venv/bin/python python/password_store.py set loan_app
   .venv/bin/python python/password_store.py set loan_test
   scripts/5_create_schema.sh
   ```

9. Check the loaded ODS release, register and verify the source batch, then load the warehouse. HARD failures stop processing. Invalid loan references and invalid months may be excluded only after full row-level quarantine has been recorded. A later successful source reload invalidates the prior gate, so rerun `dq_ods.sql` after reloading.

   ```bash
   scripts/run_sql.sh checks/dq_ods.sql "release_id=$RELEASE"
   export LOAN_RAW_MANIFEST=../data/my_manifest.csv
   RUN_ID=$(.venv/bin/python python/etl_log.py start release "$RELEASE")
   BATCH_ID=$(.venv/bin/python python/lineage_batch.py begin "$RELEASE" "$RUN_ID")
   .venv/bin/python python/lineage_batch.py finish "$RELEASE" "$BATCH_ID"
   scripts/2_load_dw_release.sh "$RELEASE"
   .venv/bin/python python/etl_log.py end "$RUN_ID" SUCCESS
   ```

   `finish` checks every file this release has in ODS against its archive in the manifest (ZIP size and SHA-256, the member inside the ZIP, the extracted text, and a row-by-row fingerprint of ODS) and only then marks the batch verified. Use the release label `R45` or `R46` for the earlier layout and `R47` for the July 2026 layout. The warehouse loader refuses to publish if ODS has a load newer than the latest verified batch. Each DWS and ADS publication is recorded in `dw_calculation` with its row count, result digest, source batch, parent calculation, and run.

   The warehouse loader validates and exchanges the release fact partition before recomputing summaries. If summary processing fails after exchange, the detail is already new: investigate and rerun.

   For a newer-layout sample, independently reconcile every result with the same raw files and matching official headers. The scripts take one year's files, so load that year alone into a release label of its own (for example `R47Y2010`) to reconcile it. The segmented check also needs the two official Census reference files named in `source/dim/load_dim_geography.sql`; put them in `CENSUS_DIR`.

   ```bash
   ORIG_HEADER=/path/to/origination_data_file_header.txt
   PERF_HEADER=/path/to/performance_data_file_header.txt
   CENSUS_DIR=/path/to/census_reference_files
   .venv/bin/python python/reconcile_dlq60_curve.py "$RELEASE" "$EXTRACT_DIR/sample_orig_$YEAR.txt" "$ORIG_HEADER" "$EXTRACT_DIR/sample_perf_$YEAR.txt" "$PERF_HEADER"
   .venv/bin/python python/reconcile_transition.py "$RELEASE" "$EXTRACT_DIR/sample_perf_$YEAR.txt" "$PERF_HEADER"
   .venv/bin/python python/reconcile_modification.py "$RELEASE" "$EXTRACT_DIR/sample_perf_$YEAR.txt" "$PERF_HEADER"
   .venv/bin/python python/reconcile_segment.py "$RELEASE" "$EXTRACT_DIR/sample_orig_$YEAR.txt" "$ORIG_HEADER" "$EXTRACT_DIR/sample_perf_$YEAR.txt" "$PERF_HEADER" "$CENSUS_DIR"
   ```


   For release comparison, fully load both releases first, then run `scripts/run_sql.sh source/ads/run_compare_releases.sql old_release=OLD new_release=NEW`. To load a corrected release using a baseline, run `scripts/2_load_dw_release.sh NEW OLD`. Unchanged loan summaries are copied; affected loans are recomputed. Without a baseline the loader recomputes everything. `python/reconcile_loan_bands.py` is an additional check expecting all three releases R45, R46, and R47.

10. Select review candidates and publish them to the review database. The PL/SQL procedure `candidate_publish.stage_month` applies the review rule in effect for the reporting month to the release: a loan becomes a candidate when it is 60+ days delinquent this month and was not last month. It stages each candidate with its origination fields and up to 13 months of history, and a SHA-256 digest of that evidence. The importer then rechecks every staged row on its own (business keys, rule, months, digests) and merges the candidates and evidence in one transaction. The delivery ID is derived from the staged content, so running the same month again changes nothing. Choose a reporting month represented in the fact table.

    ```bash
    MONTH=2009-06-01
    scripts/run_sql.sh source/dim/run_load_dim_review_rule.sql
    .venv/bin/python python/candidate_import.py "$RELEASE" "$MONTH"
    ```

    With the four sample years of R47 and June 2009, 466 candidates are published (from the 2006 and 2007 vintages; the later two had not yet been originated).

11. Run the review application, then capture its changes into the warehouse. `11_set_demo_passwords.sh` writes random passwords for `analyst_demo` and `manager_demo` to `app/demo-users.local.txt` (not in git). Open `http://localhost:8081`, sign in as the manager, open a case from Review Candidates, assign it to the analyst, sign in as the analyst to add a note, then close or escalate it as the manager. The monthly report is recomputed from the warehouse, so run the extraction after working in the application, then reconcile the warehouse with OLTP.

    ```bash
    scripts/11_set_demo_passwords.sh
    scripts/12_run_app.sh
    # in another terminal, after using the application:
    scripts/run_sql.sh source/dim/run_load_dim_review_rule.sql
    scripts/run_sql.sh source/dwd/run_cdc_review.sql
    scripts/run_sql.sh checks/dq_review_cdc.sql
    ```

    `run_cdc_review.sql` reads cases and status changes modified since the last watermark minus a 10-minute overlap window, merges them into `dwd_review_case` and `dwd_review_case_event`, updates the SCD2 user dimension, recomputes `ads_review_case_monthly`, and records the run and its calculation in one transaction. `dq_review_cdc.sql` fails if case counts, status-change counts, current statuses, or the report total differ between OLTP and the warehouse.

## End-to-end test

`scripts/run_end_to_end.sh` runs steps 1–11 on an empty database in one go and stops at the first failure: it deploys every object, loads the sample years, builds every layer, publishes candidates for one month and proves a second run changes nothing, starts the web application and walks one case through open, assign, note, escalate, and close over HTTP as the two demo users, captures the review changes into the warehouse, reconciles them with OLTP, checks the monthly review report, and prints the space each layer uses. It commits data, so it runs only against the `E2E` database target: a separate container on port 1524 with its own data volume.

```bash
docker volume create oracle-e2e-data
docker run -d --name oracle-e2e -p 127.0.0.1:1524:1521 -e ENABLE_ARCHIVELOG=false -e ENABLE_FORCE_LOGGING=false -v oracle-e2e-data:/opt/oracle/oradata container-registry.oracle.com/database/free:latest
export LOAN_DW_TARGET=E2E
for user in loan_dw loan_oltp loan_app loan_test; do .venv/bin/python python/password_store.py set $user; done
LOAN_RAW_MANIFEST=../data/my_manifest.csv scripts/run_end_to_end.sh R47 2009-06-01 2006 2007 2010 2015 > logs/e2e.log 2>&1
tail -n 30 logs/e2e.log
```

The run ends with “End-to-end test passed”. It takes about 20 minutes on a laptop. With the four years the warehouse account uses about 5,460 MiB (ODS 2,622, DWD 2,614, ADS 114, DIM 88, DWS 24, the rest under 3) and the review account about 4 MiB.

## Dashboards

The Tableau workbook `dashboards/loan_risk_dashboards.twb` has four dashboards: roll rates, vintage delinquency, modification outcomes, and cure and final outcome. It reads CSV exports of the analysis tables from `dashboards/data/` (not in git). Export the CSV files for Tableau, then open the workbook in Tableau:

```bash
.venv/bin/python python/export_dashboard_csv.py "$RELEASE" dashboards/data
```

## Tests

The tests write data and roll it back, so they run only on a database marked TEST (step 8). Run step 11's rule sync and extraction once before the SQL tests, so the rule and user dimensions are populated.

The release-comparison test needs releases R45 and R46 of the 2010 sample as well. Loaded with the four R47 years, the warehouse no longer fits in the 8 GiB USERS file: an administrator must provide a USERS file of at least 10 GiB before loading the two additional releases. The candidate importer continues to require at least 500 MiB free and keeps its 160 MiB candidate budget. On this fresh development database, run the following through the container's SQL*Plus administrator session in `FREEPDB1`:

```sql
whenever sqlerror exit failure rollback
declare
   l_file varchar2(1000);
   l_bytes number;
begin
   select file_name, bytes into l_file, l_bytes
   from dba_data_files where tablespace_name = 'USERS';
   if l_bytes < 10737418240 then
      execute immediate 'alter database datafile '
         || dbms_assert.enquote_literal(l_file) || ' resize 10g';
   end if;
end;
/
```

Python tests (ODS loading and exchange, candidate selection and publication, release comparison and targeted recomputation). `test/test_targeted_baseline.py` needs releases R45 and R46 of the same origination year fully loaded (step 9 for each): it checks that a targeted recomputation of R46 from the R45 baseline gives exactly the same DWS and ADS rows as the full load, that a release with no state transitions completes, and that a baseline with a missing modification summary is rejected before any target data changes:

```bash
.venv/bin/python -m unittest discover -s test -p "test_*.py"
```

Web application tests (security requirements, full workflow from candidate to monthly report, concurrent decisions, password change and lockout, error IDs); they use the test account `loan_test` and roll back:

```bash
scripts/12_run_app.sh test
```

SQL tests. The five suites below use [utPLSQL](https://github.com/utPLSQL/utPLSQL) v3.2.3, installed into the database with grants for `loan_dw`, `loan_oltp`, and `loan_test`; each file is deployed first and then run. The framework installation must also grant `create procedure` to `loan_test`, so this dedicated test account can compile its own test packages. Run `grant create procedure to loan_test;` as an administrator in `FREEPDB1` before deploying the suites:

```bash
ORACLE_USER=loan_oltp scripts/run_sql.sh test/test_review_workflow.sql
ORACLE_USER=loan_oltp scripts/run_sql.sh test/run_utplsql.sql suite_name=test_review_workflow
ORACLE_USER=loan_test scripts/run_sql.sh test/test_dim_review_rule.sql
ORACLE_USER=loan_test scripts/run_sql.sh test/run_utplsql.sql suite_name=test_dim_review_rule
scripts/run_sql.sh test/test_dim_review_user.sql
scripts/run_sql.sh test/run_utplsql.sql suite_name=test_dim_review_user
ORACLE_USER=loan_test scripts/run_sql.sh test/test_review_cdc.sql
ORACLE_USER=loan_test scripts/run_sql.sh test/run_utplsql.sql suite_name=test_review_cdc
ORACLE_USER=loan_test scripts/run_sql.sh test/test_ads_review_case_monthly.sql
ORACLE_USER=loan_test scripts/run_sql.sh test/run_utplsql.sql suite_name=test_ads_review_case_monthly
```

These SQL checks need no framework:

```bash
.venv/bin/python python/check_app_privileges.py
ORACLE_USER=loan_oltp scripts/run_sql.sh test/test_oltp_dw_privileges.sql
scripts/run_sql.sh test/test_dw_oltp_write_privileges.sql
scripts/run_sql.sh test/test_review_reopen_duration.sql
ORACLE_USER=loan_test scripts/run_sql.sh test/test_review_dq011_bypass.sql
```

`test_review_cdc.sql` proves the late-commit case: with no overlap window a change committed after its timestamp was passed is missed, and with the 10-minute window it is caught. `check_app_privileges.py` creates its own candidate, runs `test_app_user_privileges.sql` logged in as the web account, and cleans up; the SQL test and proves it cannot drop or create tables, delete cases, change other columns, or read ODS, underlying analysis tables, or quality results.
