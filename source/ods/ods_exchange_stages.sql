-- Name: ods_exchange_stages.sql
-- Purpose: create permanent exchange staging tables for the four file-partitioned ODS tables; the staging tables keep
--          the original primary keys.
-- Usage: scripts/run_sql.sh source/ods/ods_exchange_stages.sql
-- Requires: the four partitioned ODS tables created
-- Called by: deployment from scratch (see Setup in README)

-- The format checker cannot parse "for exchange with table" yet.
-- noqa: disable=all
create table ods_orig_stage for exchange with table ods_orig;
alter table ods_orig_stage add constraint ods_orig_stage_pk
   primary key (release_id, loan_identifier);

create table ods_perf_stage for exchange with table ods_perf;
alter table ods_perf_stage add constraint ods_perf_stage_pk
   primary key (release_id, loan_identifier, monthly_reporting_period);

create table ods_orig_pre202607_stage for exchange with table ods_orig_pre202607;
alter table ods_orig_pre202607_stage add constraint ods_orig_pre202607_stage_pk
   primary key (release_id, loan_sequence_number);

create table ods_perf_pre202607_stage for exchange with table ods_perf_pre202607;
alter table ods_perf_pre202607_stage add constraint ods_perf_pre202607_stage_pk
   primary key (release_id, loan_sequence_number, monthly_reporting_period);
-- noqa: enable=all
