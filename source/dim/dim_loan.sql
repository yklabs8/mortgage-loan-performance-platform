-- Loan dimension for the first warehouse path. One row per loan and release.
create table dim_loan (
   first_payment_date date
   , loan_identifier varchar2(12)
   , origination_year number(4)
   , origination_quarter number(1)
   , release_id varchar2(10) not null
   , data_source varchar2(3) not null
   , loan_key number generated always as identity
   , constraint dim_loan_pk primary key (loan_key)
   , constraint dim_loan_release_loan_uk unique (release_id, loan_identifier)
);
