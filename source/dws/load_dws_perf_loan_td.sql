-- Summarize the first 60+ month for every loan, including loans with no monthly row yet.
create or replace procedure load_dws_perf_loan_td(
   in_release_id in varchar2
) is
   l_dim_rows pls_integer;
   l_release_rows pls_integer;
begin
   delete from dws_perf_loan_td
   where release_id = in_release_id;

   insert into dws_perf_loan_td (
      loan_identifier
      , origination_year
      , origination_quarter
      , first_payment_date
      , months_reported
      , last_reporting_period
      , first_dlq60_period
      , first_dlq60_mob
      , release_id
   )
   with
   dwd as (
      select
         loan_identifier
         , monthly_reporting_period
         , current_loan_delinquency_status
      from dwd_loan_monthly_perf
      where release_id = in_release_id
   )

   , perf as (
      select
         w.loan_identifier
         , w.monthly_reporting_period
         , case when s.is_dlq60 = 'Y' then 1 else 0 end as is_dlq60
      from dwd w
      left join dim_delinquency_status s
         on w.current_loan_delinquency_status = s.status_code
   )

   , by_loan as (
      select
         loan_identifier
         , count(*) as months_reported
         , max(monthly_reporting_period) as last_reporting_period
         , min(
            case when is_dlq60 = 1 then monthly_reporting_period end
         ) as first_dlq60_period
      from perf
      group by loan_identifier
   )

   , dim as (
      select
         loan_identifier
         , origination_year
         , origination_quarter
         , first_payment_date
         , release_id
      from dim_loan
      where release_id = in_release_id
   )

   select
      d.loan_identifier
      , d.origination_year
      , d.origination_quarter
      , d.first_payment_date
      , coalesce(b.months_reported, 0) as months_reported
      , b.last_reporting_period
      , b.first_dlq60_period
      , months_between(b.first_dlq60_period, d.first_payment_date)
      + 1 as first_dlq60_mob
      , d.release_id
   from dim d
   left join by_loan b
      on d.loan_identifier = b.loan_identifier;

   select count(*)
   into l_dim_rows
   from dim_loan
   where release_id = in_release_id;
   select count(*)
   into l_release_rows
   from dws_perf_loan_td
   where release_id = in_release_id;
   if l_release_rows = 0 or l_release_rows != l_dim_rows then
      raise_application_error(
         -20001
         , 'dws_perf_loan_td row count mismatch: release ' || l_release_rows
         || ', dim_loan ' || l_dim_rows
      );
   end if;
end load_dws_perf_loan_td;
/
