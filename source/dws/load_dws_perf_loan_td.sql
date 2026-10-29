-- load_dws_perf_loan_td.sql
-- Load dws perf loan td. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_dws_perf_loan_td(
   in_release_id in varchar2
   , in_only_listed in varchar2 default 'N'
) is
   l_dim_rows pls_integer;
   l_release_rows pls_integer;
begin
   delete from dws_perf_loan_td
   where
      release_id = in_release_id
      and (
         in_only_listed = 'N'
         or loan_identifier in (
            select loan_identifier
            from dw_recompute_loan
            where release_id = in_release_id
         )
      );

   insert into dws_perf_loan_td (
      loan_identifier
      , origination_year
      , origination_quarter
      , first_payment_date
      , months_reported
      , last_reporting_period
      , first_dlq60_period
      , first_dlq60_mob
      , zero_balance_code
      , zero_balance_effective_date
      , release_id
   )
   with

   scope_listed as (
      select loan_identifier
      from dw_recompute_loan
      where
         release_id = in_release_id
         and change_kind != 'REMOVED'
         and in_only_listed = 'Y'
   )

   , scope as (
      select loan_identifier
      from dim_loan
      where release_id = in_release_id and in_only_listed = 'N'
      union all
      select loan_identifier
      from scope_listed
   )

   , dwd as (
      select
         loan_identifier
         , monthly_reporting_period
         , current_loan_delinquency_status
         , zero_balance_code
         , zero_balance_effective_date
      from dwd_loan_monthly_perf
      where release_id = in_release_id and in_only_listed = 'N'
      union all
      select
         w.loan_identifier
         , w.monthly_reporting_period
         , w.current_loan_delinquency_status
         , w.zero_balance_code
         , w.zero_balance_effective_date
      from dwd_loan_monthly_perf w
      inner join scope_listed sl
         on w.loan_identifier = sl.loan_identifier
      where w.release_id = in_release_id  -- noqa: RF02,RF03
   )

   , perf as (
      select
         w.loan_identifier
         , w.monthly_reporting_period
         , w.zero_balance_code
         , w.zero_balance_effective_date
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
      where
         release_id = in_release_id
         and loan_identifier in (select sc.loan_identifier from scope sc)
   )

   , zero_balance as (
      select
         loan_identifier
         , zero_balance_code
         , zero_balance_effective_date
         , row_number() over (
            partition by loan_identifier order by monthly_reporting_period desc
         ) as rn
      from perf
      where zero_balance_code is not null
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
      , z.zero_balance_code
      , z.zero_balance_effective_date
      , d.release_id
   from dim d
   left join by_loan b
      on d.loan_identifier = b.loan_identifier
   left join zero_balance z
      on
         d.loan_identifier = z.loan_identifier
         and z.rn = 1;

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
