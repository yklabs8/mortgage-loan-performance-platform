-- find_recompute_loans.sql
-- Find recompute loans. See docs/metric_definitions.md for analytical definitions.
create or replace procedure find_recompute_loans(
   in_base_release_id in varchar2
   , in_release_id in varchar2
) is
begin
   delete from dw_recompute_loan
   where release_id = in_release_id;

   insert into dw_recompute_loan (
      release_id, base_release_id, loan_identifier, change_kind
   )
   with

   base_dim as (
      select
         loan_identifier
         , origination_year
         , origination_quarter
         , first_payment_date
      from dim_loan
      where release_id = in_base_release_id
   )

   , new_dim as (
      select
         loan_identifier
         , origination_year
         , origination_quarter
         , first_payment_date
      from dim_loan
      where release_id = in_release_id
   )

   , base_perf as (
      select
         loan_identifier
         , monthly_reporting_period
         , current_loan_delinquency_status
         , zero_balance_code
         , zero_balance_effective_date
         , modification_flag
         , data_source
      from dwd_loan_monthly_perf
      where release_id = in_base_release_id
   )

   , new_perf as (
      select
         loan_identifier
         , monthly_reporting_period
         , current_loan_delinquency_status
         , zero_balance_code
         , zero_balance_effective_date
         , modification_flag
         , data_source
      from dwd_loan_monthly_perf
      where release_id = in_release_id
   )

   , dim_changed as (
      select coalesce(n.loan_identifier, b.loan_identifier) as loan_identifier
      from base_dim b
      full outer join new_dim n
         on b.loan_identifier = n.loan_identifier
      where
         b.loan_identifier is null
         or n.loan_identifier is null
         or decode(b.origination_year, n.origination_year, 0, 1) = 1
         or decode(b.origination_quarter, n.origination_quarter, 0, 1) = 1
         or decode(b.first_payment_date, n.first_payment_date, 0, 1) = 1
   )

   , perf_changed as (
      select coalesce(n.loan_identifier, b.loan_identifier) as loan_identifier
      from base_perf b
      full outer join new_perf n
         on
            b.loan_identifier = n.loan_identifier
            and b.monthly_reporting_period = n.monthly_reporting_period
      where
         b.loan_identifier is null
         or n.loan_identifier is null
         or decode(
            b.current_loan_delinquency_status
            , n.current_loan_delinquency_status
            , 0
            , 1
         ) = 1
         or decode(b.zero_balance_code, n.zero_balance_code, 0, 1) = 1
         or decode(
            b.zero_balance_effective_date
            , n.zero_balance_effective_date
            , 0
            , 1
         ) = 1
         or decode(b.modification_flag, n.modification_flag, 0, 1) = 1
         or decode(b.data_source, n.data_source, 0, 1) = 1
   )

   , changed as (
      select loan_identifier
      from dim_changed
      union
      select loan_identifier
      from perf_changed
   )

   , params as (
      select
         in_release_id as release_id
         , in_base_release_id as base_release_id
      from dual
   )

   select
      pr.release_id
      , pr.base_release_id
      , coalesce(n.loan_identifier, b.loan_identifier) as loan_identifier
      , case
         when b.loan_identifier is null then 'NEW'
         when n.loan_identifier is null then 'REMOVED'
         else 'CHANGED'
      end as change_kind
   from new_dim n
   full outer join base_dim b
      on n.loan_identifier = b.loan_identifier
   cross join params pr
   where
      n.loan_identifier is null
      or b.loan_identifier is null
      or exists (
         select 1
         from changed c
         where
            c.loan_identifier = coalesce(n.loan_identifier, b.loan_identifier)
      );
end find_recompute_loans;
/
