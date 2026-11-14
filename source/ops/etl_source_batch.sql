-- One batch per load of a release; only SUCCESS / LEGACY_VERIFIED batches may be referenced by calculations.
create table etl_source_batch (
   source_batch_id number generated always as identity
   , data_source varchar2(10) not null
   , release_id varchar2(10) not null
   , run_id number
   , loaded_at timestamp(6) default systimestamp not null
   , verified_at timestamp(6)
   , status varchar2(20) not null
   , format_version varchar2(30) not null
   , row_count number -- noqa: RF04
   , batch_digest varchar2(64)
   , error_message varchar2(1000)
   , constraint etl_source_batch_pk primary key (source_batch_id)
   , constraint etl_source_batch_run_fk foreign key (run_id)
   references etl_run (run_id)
   , constraint etl_source_batch_status_ck check (
      status in ('STARTED', 'FAILED', 'SUCCESS', 'LEGACY_VERIFIED')
   )
);

create index etl_source_batch_release_ix
on etl_source_batch (release_id, source_batch_id);
