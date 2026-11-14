-- Name: etl_run_tables.sql
-- Purpose: create the run log tables for pipeline runs:
--          etl_run has one row per run (which releases, success or failure);
--          etl_run_step has one row per step (start, end, row count, exit code, last lines of output on failure, location of the full log).
--          On failure it shows which run, which step, and why; resuming a run uses it to find the failed step
-- Called by: deployment scripts or manually
-- Called by: scripts/run_sql.sh source/ops/etl_run_tables.sql (run once)

create table etl_run (
   run_id number generated always as identity
   , pipeline varchar2(30) not null
   , run_args varchar2(200) not null
   , status varchar2(10) not null
   , started_at timestamp(6) default systimestamp not null
   , ended_at timestamp(6)
   , constraint etl_run_pk primary key (run_id)
   , constraint etl_run_status_ck check (
      status in ('RUNNING', 'SUCCESS', 'FAILED')
   )
);

create table etl_run_step (
   run_id number not null
   , step_no number not null
   , step_name varchar2(60) not null
   , status varchar2(10) not null
   , started_at timestamp(6) default systimestamp not null
   , ended_at timestamp(6)
   , processed_rows number
   , exit_code number
   , error_tail varchar2(4000)
   , log_file varchar2(400) not null
   , constraint etl_run_step_pk primary key (run_id, step_no)
   , constraint ers_er_fk foreign key (run_id) references etl_run (run_id)
   , constraint etl_run_step_status_ck check (
      status in ('RUNNING', 'SUCCESS', 'FAILED', 'SKIPPED')
   )
);

-- Comment lines exceed 80 characters; line-length checks are off for this block (platform convention)
-- noqa: disable=LT05
comment on table etl_run is 'Operations: one row per pipeline run';
comment on column etl_run.run_id is 'Run ID';
comment on column etl_run.pipeline is 'Pipeline name, for example release (from raw files to reports)';
comment on column etl_run.run_args is 'Arguments, for example "R45 R46"; resuming finds the previous run with the same arguments';
comment on column etl_run.status is 'RUNNING (stays here if the process is killed) / SUCCESS / FAILED';
comment on column etl_run.started_at is 'Start time';
comment on column etl_run.ended_at is 'End time';
comment on table etl_run_step is 'Operations: one row per pipeline step';
comment on column etl_run_step.run_id is 'Run this step belongs to';
comment on column etl_run_step.step_no is 'Step number (from 1, in execution order)';
comment on column etl_run_step.step_name is 'Step name such as R45:load_ods (release:step); used to choose the step to start from';
comment on column etl_run_step.status is 'RUNNING / SUCCESS / FAILED / SKIPPED (skipped by a restart point or not applicable to this release)';
comment on column etl_run_step.started_at is 'Start time';
comment on column etl_run_step.ended_at is 'End time';
comment on column etl_run_step.processed_rows is 'Rows after this step (on success, per step: ODS rows, detail rows, extracted rows); empty where not meaningful';
comment on column etl_run_step.exit_code is 'Command exit code, 0 = success';
comment on column etl_run_step.error_tail is 'Last 20 log lines on failure (the full log is in log_file)';
comment on column etl_run_step.log_file is 'Log file with the full output of this step (logs/ in the repository, not in git)';
-- noqa: enable=LT05
