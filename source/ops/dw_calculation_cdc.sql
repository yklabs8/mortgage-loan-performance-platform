-- Non-file inputs of the monthly review report: actual CDC extraction ID, watermark, row count, rule versions.
create table dw_calculation_cdc (
   calc_id number not null
   , cdc_run_id number not null
   , source_name varchar2(30) not null
   , from_ts timestamp(6) not null
   , to_ts timestamp(6) not null
   , extracted_rows number not null
   , loaded_rows number
   , rule_version varchar2(40) not null
   , input_digest varchar2(64)
   , constraint dw_calculation_cdc_pk primary key (calc_id, cdc_run_id)
   , constraint dw_calculation_cdc_calc_fk foreign key (calc_id)
   references dw_calculation (calc_id)
   , constraint dw_calculation_cdc_run_fk foreign key (cdc_run_id)
   references etl_cdc_run (run_id)
);
