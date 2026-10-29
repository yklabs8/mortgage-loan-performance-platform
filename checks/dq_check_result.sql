-- dq_check_result.sql
-- Dq check result. See docs/metric_definitions.md for analytical definitions.
create table dq_run (
   run_id number generated always as identity
   , release_id varchar2(10) not null
   , check_scope varchar2(10) not null
   , started_at timestamp default systimestamp not null
   , constraint dq_run_pk primary key (run_id)
   , constraint dq_run_check_scope_ck check (
      check_scope in ('ODS', 'DW', 'REVIEW')
   )
);

create table dq_check_result (
   run_id number not null
   , release_id varchar2(10) not null
   , dw_layer varchar2(10) not null
   , rule_id varchar2(10) not null
   , severity varchar2(4) not null
   , rule_desc varchar2(200) not null
   , bad_count number not null
   , checked_at timestamp default systimestamp not null
   , constraint dq_check_result_pk primary key (run_id, rule_id)
   , constraint dq_check_result_severity_ck check (severity in ('HARD', 'WARN'))
   , constraint dcr_dr_fk foreign key (run_id) references dq_run (run_id)
);

create or replace view dq_check_latest as
with ranked as (
   select
      release_id
      , dw_layer
      , rule_id
      , severity
      , rule_desc
      , bad_count
      , checked_at
      , run_id
      , row_number() over (
         partition by release_id, dw_layer, rule_id order by run_id desc
      ) as rn
   from dq_check_result
)

select
   release_id
   , dw_layer
   , rule_id
   , severity
   , rule_desc
   , bad_count
   , checked_at
   , run_id
from ranked
where rn = 1;

-- noqa: disable=LT05
comment on table dq_run is 'Data-quality run ledger: one row per execution of dq_ods.sql or dq_dw.sql';
comment on column dq_run.run_id is 'Run ID; increasing values identify newer runs';
comment on column dq_run.release_id is 'Release checked';
comment on column dq_run.check_scope is 'ODS = source-layer checks; DW = detail, summary, and analysis checks';
comment on column dq_run.started_at is 'Start time';
comment on table dq_check_result is 'Data-quality results: one row per run and rule; history is retained. DWD/DWS/ADS-prefixed rules are project additions.';
comment on column dq_check_result.run_id is 'Parent dq_run ID';
comment on column dq_check_result.release_id is 'Data release, e.g. R47';
comment on column dq_check_result.dw_layer is 'Checked layer: ODS / DWD / DWS / ADS; dw_layer avoids an Oracle reserved word';
comment on column dq_check_result.rule_id is 'Rule identifier, e.g. DQ004';
comment on column dq_check_result.severity is 'HARD = fail the run; WARN = record only';
comment on column dq_check_result.rule_desc is 'Rule description';
comment on column dq_check_result.bad_count is 'Invalid row or loan count; zero passes. Reconciliation failures record 1.';
comment on column dq_check_result.checked_at is 'Check time';
comment on table dq_check_latest is 'Latest run result per release, layer, and rule';
-- noqa: enable=LT05
