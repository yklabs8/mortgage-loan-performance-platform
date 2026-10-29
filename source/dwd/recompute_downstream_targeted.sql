-- recompute_downstream_targeted.sql
-- Recompute downstream targeted. See docs/metric_definitions.md for analytical definitions.
create or replace procedure recompute_downstream_targeted(
   in_base_release_id in varchar2
   , in_release_id in varchar2
) is
   l_base_dim_rows pls_integer;
   l_base_dwd_rows pls_integer;
   l_base_dws_rows pls_integer;
   l_base_curve_rows pls_integer;
   l_base_transition_rows pls_integer;
   l_expected_transition_rows pls_integer;
   l_base_mod_diff pls_integer;
   l_new_dim_rows pls_integer;
   l_new_dwd_rows pls_integer;
begin
   if in_base_release_id = in_release_id then
      raise_application_error(-20013, 'Base release must differ from the new release: ' || in_release_id);
   end if;
   select count(*)
   into l_base_dim_rows
   from dim_loan
   where release_id = in_base_release_id;
   select count(*)
   into l_base_dwd_rows
   from dwd_loan_monthly_perf
   where release_id = in_base_release_id;
   select count(*)
   into l_base_dws_rows
   from dws_perf_loan_td
   where release_id = in_base_release_id;
   if l_base_dim_rows = 0 or l_base_dwd_rows = 0 or l_base_dws_rows = 0 then
      raise_application_error(
         -20013, 'Base release has incomplete DIM/DWD/DWS data: '
         || in_base_release_id
      );
   end if;
   select count(*)
   into l_base_curve_rows
   from ads_vintage_dlq60_curve
   where release_id = in_base_release_id;
   select coalesce(sum(loan_count), 0)
   into l_base_transition_rows
   from ads_dlq_transition_monthly
   where release_id = in_base_release_id;
   select count(*)
   into l_expected_transition_rows
   from (
      select
         months_between(
            monthly_reporting_period
            , lag(monthly_reporting_period) over (
               partition by loan_identifier order by monthly_reporting_period
            )
         ) as gap_months
      from dwd_loan_monthly_perf
      where release_id = in_base_release_id
   ) gaps
   where gap_months = 1;
   if l_base_curve_rows = 0
   or l_base_transition_rows != l_expected_transition_rows then
      raise_application_error(
         -20013, 'Base release curve or transition results are absent or incomplete: '
         || in_base_release_id
      );
   end if;

   with expected as (
      select distinct loan_identifier
      from dwd_loan_monthly_perf
      where release_id = in_base_release_id and modification_flag = 'Y'
   )

   , actual as (
      select loan_identifier
      from dws_mod_loan_td
      where release_id = in_base_release_id
   )

   select count(*)
   into l_base_mod_diff
   from expected
   full outer join actual on expected.loan_identifier = actual.loan_identifier
   where expected.loan_identifier is null or actual.loan_identifier is null;
   if l_base_mod_diff > 0 then
      raise_application_error(
         -20013, 'Base release modification summary differs from detail: '
         || in_base_release_id || ', difference ' || l_base_mod_diff || ' loans'
      );
   end if;

   select count(*)
   into l_new_dim_rows
   from dim_loan
   where release_id = in_release_id;
   select count(*)
   into l_new_dwd_rows
   from dwd_loan_monthly_perf
   where release_id = in_release_id;
   if l_new_dim_rows = 0 or l_new_dwd_rows = 0 then
      raise_application_error(
         -20013, 'New release has incomplete DIM/DWD data: ' || in_release_id
      );
   end if;

   find_recompute_loans(in_base_release_id, in_release_id);

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
      , zero_balance_code
      , zero_balance_effective_date
      , release_id
   )
   with listed as (
      select loan_identifier
      from dw_recompute_loan
      where release_id = in_release_id
   )

   select
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
      , in_release_id as release_id
   from dws_perf_loan_td
   where
      release_id = in_base_release_id
      and loan_identifier not in (select ls.loan_identifier from listed ls);
   load_dws_perf_loan_td(in_release_id, 'Y');

   delete from dws_mod_loan_td
   where release_id = in_release_id;
   insert into dws_mod_loan_td (
      loan_identifier
      , origination_year
      , first_mod_period
      , mod_count
      , is_dlq60_before_mod
      , first_redefault_period
      , state_12m
      , release_id
   )
   with listed as (
      select loan_identifier
      from dw_recompute_loan
      where release_id = in_release_id
   )

   select
      loan_identifier
      , origination_year
      , first_mod_period
      , mod_count
      , is_dlq60_before_mod
      , first_redefault_period
      , state_12m
      , in_release_id as release_id
   from dws_mod_loan_td
   where
      release_id = in_base_release_id
      and loan_identifier not in (select ls.loan_identifier from listed ls);
   load_dws_mod_loan_td(in_release_id, 'Y');

   load_ads_vintage_dlq60_curve(in_release_id);
   load_ads_dlq_transition_monthly(in_release_id, in_base_release_id);
   load_ads_modification_outcome(in_release_id);
   load_ads_dlq_transition_segment(in_release_id);
   load_ads_final_outcome_segment(in_release_id);
   load_ads_cure_redefault_segment(in_release_id);
   load_ads_vintage_dlq60_segment(in_release_id);
   load_ads_modification_segment(in_release_id);
end recompute_downstream_targeted;
/
