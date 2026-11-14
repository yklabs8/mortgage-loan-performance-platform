-- Which DWS calculation an ADS calculation used, linked by calculation ID.
create table dw_calculation_parent (
   calc_id number not null
   , parent_calc_id number not null
   , constraint dw_calculation_parent_pk primary key (calc_id, parent_calc_id)
   , constraint dw_calculation_parent_calc_fk foreign key (calc_id)
   references dw_calculation (calc_id)
   , constraint dw_calculation_parent_parent_fk foreign key (parent_calc_id)
   references dw_calculation (calc_id)
);
