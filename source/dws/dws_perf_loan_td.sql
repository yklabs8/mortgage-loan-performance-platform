-- One row per loan and release for the cumulative delinquency curve.
create table dws_perf_loan_td (
   loan_identifier varchar2(12) not null
   , origination_year number(4) not null
   , origination_quarter number(1) not null
   , first_payment_date date not null
   , months_reported number not null
   , last_reporting_period date
   , first_dlq60_period date
   , first_dlq60_mob number
   , release_id varchar2(10) not null
   , constraint dws_perf_loan_td_pk primary key (release_id, loan_identifier)
);
