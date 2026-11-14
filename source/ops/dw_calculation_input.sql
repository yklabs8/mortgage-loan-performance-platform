-- Verified source batches used by a calculation; TARGET and BASE are kept apart and never inferred from release names.
create table dw_calculation_input (
   calc_id number not null
   , source_batch_id number not null
   , input_role varchar2(10) not null
   , constraint dw_calculation_input_pk primary key (
      calc_id, source_batch_id, input_role
   )
   , constraint dw_calculation_input_calc_fk foreign key (calc_id)
   references dw_calculation (calc_id)
   , constraint dw_calculation_input_batch_fk foreign key (source_batch_id)
   references etl_source_batch (source_batch_id)
   , constraint dw_calculation_input_role_ck check (
      input_role in ('TARGET', 'BASE')
   )
);
