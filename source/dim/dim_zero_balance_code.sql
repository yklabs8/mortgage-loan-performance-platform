-- dim_zero_balance_code.sql
-- Dim zero balance code. See docs/metric_definitions.md for analytical definitions.
create table dim_zero_balance_code (
   data_source varchar2(3) not null
   , zero_balance_code varchar2(2) not null
   , zero_balance_desc varchar2(100) not null
   , exit_state varchar2(10) not null
   , exit_state_order number not null
   , constraint dim_zero_balance_code_pk primary key (
      data_source, zero_balance_code
   )
   , constraint dim_zero_balance_code_data_source_ck check (
      data_source in ('FRE')
   )
);

-- noqa: disable=LT05
comment on table dim_zero_balance_code is 'DIM: one row per agency and Zero Balance Code. Official meanings: User Guide p.11. Codes appear in the final reporting month (p.16). Project exit categories: metric definitions section 5.';
comment on column dim_zero_balance_code.data_source is 'Source agency: FRE = Freddie Mac; foreign key paired with the fact zero-balance code';
comment on column dim_zero_balance_code.zero_balance_code is 'Unmodified agency zero-balance code';
comment on column dim_zero_balance_code.zero_balance_desc is 'Official code description (Freddie User Guide p.11)';
comment on column dim_zero_balance_code.exit_state is 'Exit state: PREPAID, LIQUIDATED, LOAN_SALE, or DEFECT (noncredit removal, including confirmed defects and repurchases)';
comment on column dim_zero_balance_code.exit_state_order is 'Exit-state display order after delinquency states, 10-13';
-- noqa: enable=LT05
