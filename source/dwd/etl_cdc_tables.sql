-- Name: etl_cdc_tables.sql
-- Purpose: create the two change data capture (CDC) tables: etl_watermark records how far each source has been extracted (the watermark);
--          etl_cdc_run records each extraction's start and end watermark and row counts, so a problem can be traced to one run and its time range
-- Called by: deployment scripts or manually
-- Called by: scripts/run_sql.sh source/dwd/etl_cdc_tables.sql (run once)

create table etl_watermark (
   source_name varchar2(30) not null
   , watermark_ts timestamp(6) not null
   , constraint etl_watermark_pk primary key (source_name)
);

create table etl_cdc_run (
   run_id number generated always as identity
   , source_name varchar2(30) not null
   , overlap_minutes number not null
   , from_ts timestamp(6) not null
   , to_ts timestamp(6) not null
   , extracted_rows number not null
   , staged_rows number
   , loaded_rows number
   , started_at timestamp(6) default systimestamp not null
   , constraint etl_cdc_run_pk primary key (run_id)
);

-- noqa: disable=LT05
comment on table etl_watermark is 'CDC watermark: the time each source was last extracted to. The next run reads from "watermark - overlap window"';
comment on column etl_watermark.source_name is 'Source, such as REVIEW_CASE or REVIEW_CASE_EVENT';
comment on column etl_watermark.watermark_ts is 'Database time when the last extraction started (not the largest timestamp read; see the header of cdc_review)';
comment on table etl_cdc_run is 'One row per CDC extraction: which time range was read and how many rows';
comment on column etl_cdc_run.run_id is 'Run ID';
comment on column etl_cdc_run.source_name is 'Source';
comment on column etl_cdc_run.overlap_minutes is 'Minutes re-read before the watermark this time (overlap window)';
comment on column etl_cdc_run.from_ts is 'Lower bound (exclusive): previous watermark - overlap window';
comment on column etl_cdc_run.to_ts is 'Upper bound (inclusive): database time when this run started, also the new watermark';
comment on column etl_cdc_run.extracted_rows is 'Rows read in this range (including rows re-read in the overlap window)';
comment on column etl_cdc_run.staged_rows is 'MERGE input rows; empty for older runs, which must not be treated as reconciled';
comment on column etl_cdc_run.loaded_rows is 'Target rows for the business keys after MERGE; overlap re-reads are counted';
comment on column etl_cdc_run.started_at is 'Run time';
-- noqa: enable=LT05
