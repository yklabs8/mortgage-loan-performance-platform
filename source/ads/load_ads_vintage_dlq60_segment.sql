-- load_ads_vintage_dlq60_segment.sql
-- Load ads vintage dlq60 segment. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_ads_vintage_dlq60_segment(
   in_release_id in varchar2
) is
begin
   delete from ads_vintage_dlq60_segment
   where release_id = in_release_id;

   insert into ads_vintage_dlq60_segment (
      origination_year, origination_quarter, months_on_book
      , segment_type, segment_value, cohort_loans, eligible_loans
      , cum_dlq60_loans, cum_dlq60_rate, release_id
   )
   with dws as (
      select
         p.loan_identifier
         , p.origination_year
         , p.origination_quarter
         , p.first_payment_date
         , p.last_reporting_period
         , p.first_dlq60_mob
      from dws_perf_loan_td p
      where p.release_id = in_release_id  -- noqa: RF02,RF03
   )

   , cutoff as (
      select max(last_reporting_period) as last_period from dws
   )

   , loans as (
      select
         p.origination_year
         , p.origination_quarter
         , p.first_dlq60_mob
         , seg.segment_type
         , seg.segment_value
         , months_between(c.last_period, p.first_payment_date) + 1 as max_mob
      from dws p
      inner join v_loan_segment seg
         on
            seg.release_id = in_release_id  -- noqa: RF02,RF03
            and p.loan_identifier = seg.loan_identifier
      cross join cutoff c
   )

   , cohort as (
      select
         origination_year
         , origination_quarter
         , segment_type
         , segment_value
         , count(*) as cohort_loans
      from loans
      group by
         origination_year, origination_quarter, segment_type, segment_value
   )

   , grid as (
      select
         base.months_on_book
         , c.origination_year
         , c.origination_quarter
         , c.segment_type
         , c.segment_value
         , c.cohort_loans
      from cohort c
      inner join ads_vintage_dlq60_curve base
         on
            base.release_id = in_release_id  -- noqa: RF02,RF03
            and c.origination_year = base.origination_year
            and c.origination_quarter = base.origination_quarter
   )

   , reach as (
      select
         origination_year
         , origination_quarter
         , segment_type
         , segment_value
         , max_mob as months_on_book
         , count(*) as reach_n
      from loans
      where max_mob >= 1
      group by
         origination_year, origination_quarter, segment_type, segment_value
         , max_mob
   )

   , raw_events as (
      select
         origination_year
         , origination_quarter
         , segment_type
         , segment_value
         , greatest(first_dlq60_mob, 1) as months_on_book
         , 1 as delta
      from loans
      where
         first_dlq60_mob is not null
         and greatest(first_dlq60_mob, 1) <= max_mob
      union all
      select
         origination_year
         , origination_quarter
         , segment_type
         , segment_value
         , max_mob + 1 as months_on_book
         , -1 as delta
      from loans
      where
         first_dlq60_mob is not null
         and greatest(first_dlq60_mob, 1) <= max_mob
   )

   , events as (
      select
         origination_year
         , origination_quarter
         , segment_type
         , segment_value
         , months_on_book
         , sum(delta) as delta
      from raw_events
      group by
         origination_year, origination_quarter, segment_type, segment_value
         , months_on_book
   )

   , joined as (
      select
         g.origination_year
         , g.origination_quarter
         , g.months_on_book
         , g.segment_type
         , g.segment_value
         , g.cohort_loans
         , coalesce(r.reach_n, 0) as reach_n
         , coalesce(e.delta, 0) as delta
      from grid g
      left join reach r
         on
            g.origination_year = r.origination_year
            and g.origination_quarter = r.origination_quarter
            and g.segment_type = r.segment_type
            and g.segment_value = r.segment_value
            and g.months_on_book = r.months_on_book
      left join events e
         on
            g.origination_year = e.origination_year
            and g.origination_quarter = e.origination_quarter
            and g.segment_type = e.segment_type
            and g.segment_value = e.segment_value
            and g.months_on_book = e.months_on_book
   )

   , curve as (
      select
         origination_year
         , origination_quarter
         , months_on_book
         , segment_type
         , segment_value
         , cohort_loans
         , sum(reach_n) over (
            partition by
               origination_year
               , origination_quarter
               , segment_type
               , segment_value
            order by months_on_book desc
            rows between unbounded preceding and current row
         ) as eligible_loans
         , sum(delta) over (
            partition by
               origination_year
               , origination_quarter
               , segment_type
               , segment_value
            order by months_on_book
            rows between unbounded preceding and current row
         ) as cum_dlq60_loans
      from joined
   )

   select
      origination_year
      , origination_quarter
      , months_on_book
      , segment_type
      , segment_value
      , cohort_loans
      , eligible_loans
      , cum_dlq60_loans
      , cum_dlq60_loans / nullif(eligible_loans, 0) as cum_dlq60_rate
      , in_release_id as release_id
   from curve;
end load_ads_vintage_dlq60_segment;
/
