-- One row per ODS source file per batch; the original ZIP and member checksums are recorded separately.
create table etl_source_batch_file (
   source_batch_id number not null
   , source_table varchar2(30) not null
   , source_file varchar2(100) not null
   , zip_path varchar2(200) not null
   , zip_sha256 varchar2(64) not null
   , zip_bytes number not null
   , member_name varchar2(200)
   , member_sha256 varchar2(64)
   , source_bytes number not null
   , source_sha256 varchar2(64) not null
   , source_rows number not null
   , ods_rows number not null
   , ods_hash varchar2(100) not null
   , constraint etl_source_batch_file_pk primary key (
      source_batch_id, source_file
   )
   , constraint etl_source_batch_file_fk foreign key (source_batch_id)
   references etl_source_batch (source_batch_id)
);
