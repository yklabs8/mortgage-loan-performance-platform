-- load_ads_dlq_transition_segment.sql
-- Load ads dlq transition segment. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_ads_dlq_transition_segment(
   in_release_id in varchar2
) is
   l_bad pls_integer;
begin
   delete from ads_dlq_transition_segment
   where release_id = in_release_id;

   insert into ads_dlq_transition_segment (
      origination_year, monthly_reporting_period, from_state, from_state_order
      , to_state, to_state_order, segment_type, segment_value, loan_count
      , release_id
   )
   with states as (
      select
         w.loan_identifier
         , w.monthly_reporting_period
         , coalesce(z.exit_state, s.dlq_state) as cur_state
         , coalesce(z.exit_state_order, s.dlq_state_order) as cur_state_order
      from dwd_loan_monthly_perf w
      left join dim_delinquency_status s
         on w.current_loan_delinquency_status = s.status_code
      left join dim_zero_balance_code z
         on
            w.data_source = z.data_source
            and w.zero_balance_code = z.zero_balance_code
      where w.release_id = in_release_id  -- noqa: RF02,RF03
   )

   , with_prev as (
      select
         loan_identifier
         , monthly_reporting_period
         , cur_state
         , cur_state_order
         , lag(monthly_reporting_period) over (
            partition by loan_identifier order by monthly_reporting_period
         ) as prev_period
         , lag(cur_state) over (
            partition by loan_identifier order by monthly_reporting_period
         ) as prev_state
         , lag(cur_state_order) over (
            partition by loan_identifier order by monthly_reporting_period
         ) as prev_state_order
      from states
   )

   select
      d.origination_year
      , p.monthly_reporting_period
      , p.prev_state
      , p.prev_state_order
      , p.cur_state
      , p.cur_state_order
      , seg.segment_type
      , seg.segment_value
      , count(*) as loan_count
      , in_release_id as release_id  -- noqa: RF02,RF03
   from with_prev p
   inner join dim_loan d
      on
         d.release_id = in_release_id  -- noqa: RF02,RF03
         and p.loan_identifier = d.loan_identifier
   inner join v_loan_segment seg
      on
         d.release_id = seg.release_id
         and d.loan_identifier = seg.loan_identifier
   where months_between(p.monthly_reporting_period, p.prev_period) = 1
   group by
      d.origination_year, p.monthly_reporting_period
      , p.prev_state, p.prev_state_order, p.cur_state, p.cur_state_order
      , seg.segment_type, seg.segment_value;

   select count(*) into l_bad
   from (
      select
         segment_type
         , sum(loan_count) as segment_total
      from ads_dlq_transition_segment
      where release_id = in_release_id
      group by segment_type
   ) s
   where s.segment_total != (
      select coalesce(sum(t.loan_count), 0)
      from ads_dlq_transition_monthly t
      where t.release_id = in_release_id  -- noqa: RF02,RF03
   );
   if l_bad > 0 then
      raise_application_error(-20048, 'Segment transition totals differ from the original transition table');
   end if;
end load_ads_dlq_transition_segment;
/
