-- Every successful publication of one scope of a DWS/ADS table gets its own calculation ID.
create table dw_calculation (
   calc_id number generated always as identity
   , output_table varchar2(40) not null
   , release_id varchar2(10)
   , base_release_id varchar2(10)
   , target_scope varchar2(200) not null
   , run_id number
   , started_at timestamp(6) with time zone not null
   , published_at timestamp(6) with time zone
   , status varchar2(10) not null -- noqa: RF04
   , result_rows number
   , result_digest varchar2(64)
   , git_commit varchar2(40)
   , metric_sha256 varchar2(64)
   , parameters_json varchar2(4000)
   , algorithm_version varchar2(40) not null
   , input_cutoff timestamp(6) with time zone
   , delivery_id raw(16)  -- analysis delivery ID; empty when the result is computed in Oracle
   , constraint dw_calculation_pk primary key (calc_id)
   , constraint dw_calculation_run_fk foreign key (run_id)
   references etl_run (run_id)
   , constraint dw_calculation_status_ck check (
      status in ('STARTED', 'FAILED', 'SUCCESS')
   )
   , constraint dw_calculation_success_ck check (
      status != 'SUCCESS'
      or (
         published_at is not null and result_rows is not null
         and result_digest is not null
      )
   )
);

create index dw_calculation_asof_ix
on dw_calculation (output_table, release_id, base_release_id, published_at);
