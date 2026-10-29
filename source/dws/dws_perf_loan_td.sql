-- dws_perf_loan_td.sql
-- Dws perf loan td. See docs/metric_definitions.md for analytical definitions.
create table dws_perf_loan_td (
   loan_identifier varchar2(12) not null
   , origination_year number(4) not null
   , origination_quarter number(1) not null
   , first_payment_date date not null
   , months_reported number not null
   , last_reporting_period date
   , first_dlq60_period date
   , first_dlq60_mob number
   , zero_balance_code varchar2(2)
   , zero_balance_effective_date date
   , release_id varchar2(10) not null
   , constraint dws_perf_loan_td_pk primary key (release_id, loan_identifier)
);

-- noqa: disable=LT05
comment on table dws_perf_loan_td is 'DWS: one row per release and loan, summarizing performance through that release. Key: release_id and loan_identifier. Inputs: loan dimension and monthly fact. See metric definitions.';
comment on column dws_perf_loan_td.loan_identifier is 'Loan identifier';
comment on column dws_perf_loan_td.origination_year is 'Origination year from dim_loan (User Guide p.7)';
comment on column dws_perf_loan_td.origination_quarter is 'Origination quarter from dim_loan (User Guide p.7)';
comment on column dws_perf_loan_td.first_payment_date is 'First payment date from dim_loan';
comment on column dws_perf_loan_td.months_reported is 'Number of monthly records; zero for loans with no performance history';
comment on column dws_perf_loan_td.last_reporting_period is 'Last reporting month; NULL if no monthly records';
comment on column dws_perf_loan_td.first_dlq60_period is 'First 60+ reporting month; NULL if never observed';
comment on column dws_perf_loan_td.first_dlq60_mob is 'MOB at first 60+: reporting month minus first payment month plus 1. Official Loan Age can reset after modification (User Guide p.10).';
comment on column dws_perf_loan_td.zero_balance_code is 'Last zero-balance code: 01/02/03/09/15/16/96 (User Guide p.11); NULL if no exit';
comment on column dws_perf_loan_td.zero_balance_effective_date is 'Effective date associated with the last exit code';
comment on column dws_perf_loan_td.release_id is 'Freddie data release, e.g. R47';
-- noqa: enable=LT05
