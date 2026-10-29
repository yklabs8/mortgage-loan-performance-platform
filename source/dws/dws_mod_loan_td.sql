-- dws_mod_loan_td.sql
-- Dws mod loan td. See docs/metric_definitions.md for analytical definitions.
create table dws_mod_loan_td (
   loan_identifier varchar2(12) not null
   , origination_year number(4) not null
   , first_mod_period date not null
   , mod_count number not null
   , is_dlq60_before_mod varchar2(1)
   , first_redefault_period date
   , state_12m varchar2(10)
   , release_id varchar2(10) not null
   , constraint dws_mod_loan_td_pk primary key (release_id, loan_identifier)
   , constraint dws_mod_loan_td_dlq60_ck check (
      is_dlq60_before_mod in ('Y', 'N')
   )
   , constraint dmlt_dl_fk foreign key (release_id, loan_identifier)
   references dim_loan (release_id, loan_identifier)
);

-- noqa: disable=LT05
comment on table dws_mod_loan_td is 'DWS: one row per release and loan with at least one Modification Flag Y. Derived from monthly facts and code dimensions. Metric definitions section 6.';
comment on column dws_mod_loan_td.loan_identifier is 'Loan identifier';
comment on column dws_mod_loan_td.origination_year is 'Origination year (User Guide p.7)';
comment on column dws_mod_loan_td.first_mod_period is 'First month with Modification Flag Y, meaning modified this month (User Guide p.11)';
comment on column dws_mod_loan_td.mod_count is 'Number of months with Modification Flag Y; a loan can have multiple modifications (User Guide p.11)';
comment on column dws_mod_loan_td.is_dlq60_before_mod is 'Any 60+ observation during months -12 through -1 before first modification: Y/N; NULL if no prior records. Uses dim_delinquency_status.is_dlq60. Status can reset before the modification flag appears.';
comment on column dws_mod_loan_td.first_redefault_period is 'First 60+ month in months 1-12 after first modification; NULL if absent';
comment on column dws_mod_loan_td.state_12m is 'Status in month 12 after first modification; an earlier exit uses its exit state. NULL if month 12 is not yet observable.';
comment on column dws_mod_loan_td.release_id is 'Freddie data release, e.g. R47';
-- noqa: enable=LT05
