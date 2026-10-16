-- One row per loan and reporting month in each release. The release is a list partition.
-- noqa: disable=all
create table dwd_loan_monthly_perf (
   loan_identifier varchar2(12)
   , monthly_reporting_period date
   , current_loan_delinquency_status varchar2(3)
   , data_source varchar2(3) not null
   , release_id varchar2(10) not null
   , loan_key number not null
   , period_date_key number(8) not null
   , constraint dwd_loan_monthly_perf_pk primary key (
      release_id, loan_identifier, monthly_reporting_period
   ) using index local
   , constraint dlmp_dl_fk foreign key (release_id, loan_identifier)
   references dim_loan (release_id, loan_identifier)
   , constraint dlmp_dds_fk foreign key (current_loan_delinquency_status)
   references dim_delinquency_status (status_code)
   , constraint dlmp_dl_key_fk foreign key (loan_key)
   references dim_loan (loan_key)
   , constraint dlmp_dd_fk foreign key (period_date_key)
   references dim_date (date_key)
)
partition by list (release_id) (
   partition p_default values (default)
);
-- noqa: enable=all
