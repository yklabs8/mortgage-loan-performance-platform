-- load_ads_dlq_transition_monthly.sql
-- Count only observations exactly one calendar month apart. Exit states override delinquency states. For targeted runs, copy the baseline then add new contributions and subtract old contributions for affected loans. Validate nonnegative counts and the adjacent-month total.
create or replace procedure load_ads_dlq_transition_monthly(
   in_release_id in varchar2
   , in_base_release_id in varchar2 default null
) is
   l_release_rows pls_integer;
   l_negative pls_integer;
   l_transition_total pls_integer;
   l_expected_total pls_integer;
begin
   delete from ads_dlq_transition_monthly
   where release_id = in_release_id;

   if in_base_release_id is not null then
      insert into ads_dlq_transition_monthly (
         origination_year
         , monthly_reporting_period
         , from_state
         , from_state_order
         , to_state
         , to_state_order
         , loan_count
         , release_id
      )
      select
         origination_year
         , monthly_reporting_period
         , from_state
         , from_state_order
         , to_state
         , to_state_order
         , loan_count
         , in_release_id as release_id
      from ads_dlq_transition_monthly
      where release_id = in_base_release_id;
   end if;

   merge into ads_dlq_transition_monthly t
   using (
      with

      scope_listed as (
         select
            release_id
            , loan_identifier
            , 1 as sign_value
         from dw_recompute_loan
         where
            release_id = in_release_id
            and change_kind != 'REMOVED'
            and in_base_release_id is not null
         union all
         select
            base_release_id as release_id
            , loan_identifier
            , -1 as sign_value
         from dw_recompute_loan
         where
            release_id = in_release_id
            and change_kind != 'NEW'
            and in_base_release_id is not null
      )

      , dwd as (
         select
            loan_identifier
            , monthly_reporting_period
            , current_loan_delinquency_status
            , zero_balance_code
            , data_source
            , release_id
            , 1 as sign_value
         from dwd_loan_monthly_perf
         where release_id = in_release_id and in_base_release_id is null
         union all
         select
            w.loan_identifier
            , w.monthly_reporting_period
            , w.current_loan_delinquency_status
            , w.zero_balance_code
            , w.data_source
            , w.release_id
            , sc.sign_value
         from dwd_loan_monthly_perf w
         inner join scope_listed sc
            on
               w.release_id = sc.release_id
               and w.loan_identifier = sc.loan_identifier
         where w.release_id in (in_release_id, in_base_release_id)  -- noqa: RF02,RF03
      )

      , dim as (
         select
            release_id
            , loan_identifier
            , origination_year
         from dim_loan
         where release_id in (in_release_id, in_base_release_id)
      )

      , states as (
         select /*+ use_hash(s z) */
            w.loan_identifier
            , w.monthly_reporting_period
            , w.release_id
            , w.sign_value
            , coalesce(z.exit_state, s.dlq_state) as cur_state
            , coalesce(z.exit_state_order, s.dlq_state_order) as cur_state_order
         from dwd w
         left join dim_delinquency_status s
            on w.current_loan_delinquency_status = s.status_code
         left join dim_zero_balance_code z
            on
               w.data_source = z.data_source
               and w.zero_balance_code = z.zero_balance_code
      )

      , with_prev as (
         select
            loan_identifier
            , monthly_reporting_period
            , release_id
            , sign_value
            , cur_state
            , cur_state_order
            , lag(monthly_reporting_period) over (
               partition by release_id, loan_identifier
               order by monthly_reporting_period
            ) as prev_period
            , lag(cur_state) over (
               partition by release_id, loan_identifier
               order by monthly_reporting_period
            ) as prev_state
            , lag(cur_state_order) over (
               partition by release_id, loan_identifier
               order by monthly_reporting_period
            ) as prev_state_order
         from states
      )

      , params as (
         select in_release_id as target_release_id
         from dual
      )

      select
         d.origination_year
         , p.monthly_reporting_period
         , p.prev_state as from_state
         , p.prev_state_order as from_state_order
         , p.cur_state as to_state
         , p.cur_state_order as to_state_order
         , sum(p.sign_value) as delta_count
         , pr.target_release_id as release_id
      from with_prev p
      inner join dim d
         on
            p.release_id = d.release_id
            and p.loan_identifier = d.loan_identifier
      cross join params pr
      where months_between(p.monthly_reporting_period, p.prev_period) = 1
      group by
         d.origination_year
         , p.monthly_reporting_period
         , p.prev_state
         , p.prev_state_order
         , p.cur_state
         , p.cur_state_order
         , pr.target_release_id
      having sum(p.sign_value) != 0
   ) s
      on (
         t.release_id = s.release_id
         and t.origination_year = s.origination_year
         and t.monthly_reporting_period = s.monthly_reporting_period
         and t.from_state = s.from_state
         and t.to_state = s.to_state
      )
   when matched then
      update set loan_count = t.loan_count + s.delta_count
   when not matched then
      insert (
         origination_year
         , monthly_reporting_period
         , from_state
         , from_state_order
         , to_state
         , to_state_order
         , loan_count
         , release_id
      )
      values (
         s.origination_year
         , s.monthly_reporting_period
         , s.from_state
         , s.from_state_order
         , s.to_state
         , s.to_state_order
         , s.delta_count
         , s.release_id
      );

   delete from ads_dlq_transition_monthly
   where release_id = in_release_id and loan_count = 0;

   select
      count(*) as release_rows
      , count(case when loan_count < 0 then 1 end) as negative_rows
      , coalesce(sum(loan_count), 0) as transition_total
   into l_release_rows, l_negative, l_transition_total
   from ads_dlq_transition_monthly
   where release_id = in_release_id;
   select count(*)
   into l_expected_total
   from (
      select
         months_between(
            monthly_reporting_period
            , lag(monthly_reporting_period) over (
               partition by loan_identifier order by monthly_reporting_period
            )
         ) as gap_months
      from dwd_loan_monthly_perf
      where release_id = in_release_id
   ) gaps
   where gap_months = 1;
   if l_negative > 0 or l_transition_total != l_expected_total then
      raise_application_error(
         -20001
         , 'Invalid ads_dlq_transition_monthly results: ' || in_release_id
         || ' total ' || l_release_rows || ' rows, including negative counts ' || l_negative
         || ' rows, transition total ' || l_transition_total
         || ', adjacent fact months ' || l_expected_total
      );
   end if;
end load_ads_dlq_transition_monthly;
/
