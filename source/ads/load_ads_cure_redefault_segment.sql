-- load_ads_cure_redefault_segment.sql
-- A cure requires three consecutive calendar months in C after a 60+ observation. Missing months break the streak. Count loans once for loan measures; repeated cure events remain separate. Relapse means a subsequent 60+ observation.
create or replace procedure load_ads_cure_redefault_segment(
   in_release_id in varchar2
) is
begin
   delete from ads_cure_redefault_segment
   where release_id = in_release_id;

   insert into ads_cure_redefault_segment (
      origination_year, segment_type, segment_value, dlq60_loans
      , cured_loans, cure_events, redefault_loans, cure_rate, release_id
   )
   with monthly as (
      select
         w.loan_identifier
         , w.monthly_reporting_period
         , case when s.is_dlq60 = 'Y' then 1 else 0 end as is_dlq60
         , case
            when s.dlq_state = 'C' and w.zero_balance_code is null
               then 1
            else 0
         end as is_current
      from dwd_loan_monthly_perf w
      inner join dim_delinquency_status s
         on w.current_loan_delinquency_status = s.status_code
      where w.release_id = in_release_id  -- noqa: RF02,RF03
   )

   , timeline as (
      select
         m.loan_identifier
         , m.monthly_reporting_period
         , m.is_dlq60
         , m.is_current
         , lag(m.monthly_reporting_period) over (
            partition by m.loan_identifier order by m.monthly_reporting_period
         ) as prev_period
         , lag(m.is_current) over (
            partition by m.loan_identifier order by m.monthly_reporting_period
         ) as prev_current
         , max(case when m.is_dlq60 = 1 then m.monthly_reporting_period end)
            over (
               partition by m.loan_identifier
               order by m.monthly_reporting_period
               rows between unbounded preceding and current row
            ) as last_dlq60_period
      from monthly m
   )

   , runs as (
      select
         t.loan_identifier
         , t.monthly_reporting_period
         , t.is_current
         , t.last_dlq60_period
         , sum(case
            when
               t.is_current = 1 and t.prev_current = 1
               and months_between(t.monthly_reporting_period, t.prev_period) = 1
               then 0
            else 1
         end) over (
            partition by t.loan_identifier order by t.monthly_reporting_period
            rows between unbounded preceding and current row
         ) as current_run_id
      from timeline t
   )

   , ranked as (
      select
         r.loan_identifier
         , r.monthly_reporting_period
         , r.is_current
         , r.last_dlq60_period
         , row_number() over (
            partition by r.loan_identifier, r.current_run_id
            order by r.monthly_reporting_period
         ) as current_month_number
      from runs r
   )

   , cures as (
      select
         r.loan_identifier
         , r.last_dlq60_period
         , min(r.monthly_reporting_period) as cure_period
      from ranked r
      where
         r.is_current = 1
         and r.current_month_number >= 3
         and r.last_dlq60_period is not null
      group by r.loan_identifier, r.last_dlq60_period
   )

   , cure_counts as (
      select
         c.loan_identifier
         , count(*) as cure_events
         , min(c.cure_period) as first_cure_period
      from cures c
      group by c.loan_identifier
   )

   , ever_dlq60 as (
      select
         m.loan_identifier
         , max(m.is_dlq60) as has_dlq60
      from monthly m
      group by m.loan_identifier
   )

   , redefaults as (
      select distinct m.loan_identifier
      from monthly m
      inner join cure_counts c
         on m.loan_identifier = c.loan_identifier
      where
         m.is_dlq60 = 1
         and m.monthly_reporting_period > c.first_cure_period
   )

   select
      d.origination_year
      , seg.segment_type
      , seg.segment_value
      , sum(coalesce(e.has_dlq60, 0)) as dlq60_loans
      , sum(case when c.cure_events > 0 then 1 else 0 end) as cured_loans
      , sum(coalesce(c.cure_events, 0)) as cure_events
      , sum(case when r.loan_identifier is not null then 1 else 0 end)
         as redefault_loans
      , sum(case when c.cure_events > 0 then 1 else 0 end)
      / nullif(sum(coalesce(e.has_dlq60, 0)), 0) as cure_rate
      , in_release_id as release_id  -- noqa: RF02,RF03
   from dim_loan d
   inner join v_loan_segment seg
      on
         d.release_id = seg.release_id
         and d.loan_identifier = seg.loan_identifier
   left join ever_dlq60 e
      on d.loan_identifier = e.loan_identifier
   left join cure_counts c
      on d.loan_identifier = c.loan_identifier
   left join redefaults r
      on d.loan_identifier = r.loan_identifier
   where d.release_id = in_release_id  -- noqa: RF02,RF03
   group by d.origination_year, seg.segment_type, seg.segment_value;
end load_ads_cure_redefault_segment;
/
