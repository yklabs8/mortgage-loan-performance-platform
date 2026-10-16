-- First warehouse path; source definitions and calculations are documented in docs/metric_definitions.md.

create or replace procedure load_ads_vintage_dlq60_curve(
   in_release_id in varchar2
) is
   l_inserted pls_integer;
begin
   delete from ads_vintage_dlq60_curve
   where release_id = in_release_id;

   insert into ads_vintage_dlq60_curve (
      origination_year
      , origination_quarter
      , months_on_book
      , cohort_loans
      , eligible_loans
      , cum_dlq60_loans
      , cum_dlq60_rate
      , release_id
   )
   with

   dws as (
      select
         origination_year
         , origination_quarter
         , first_payment_date
         , last_reporting_period
         , first_dlq60_mob
         , release_id
      from dws_perf_loan_td
      where release_id = in_release_id
   )

   , cutoff as (
      select max(last_reporting_period) as last_period
      from dws
   )

   , loans as (
      select
         d.origination_year
         , d.origination_quarter
         , d.first_dlq60_mob
         , d.release_id
         , months_between(c.last_period, d.first_payment_date) + 1 as max_mob
      from dws d
      cross join cutoff c
   )

   , cohort as (
      select
         origination_year
         , origination_quarter
         , release_id
         , count(*) as cohort_loans
      from loans
      group by origination_year, origination_quarter, release_id
   )

   , mob as (
      select level as months_on_book
      from dual
      connect by level <= (select max(l.max_mob) from loans l)
   )

   , curve as (
      select
         l.origination_year
         , l.origination_quarter
         , m.months_on_book
         , count(*) as eligible_loans
         , sum(
            case when l.first_dlq60_mob <= m.months_on_book then 1 else 0 end
         ) as cum_dlq60_loans
      from loans l
      inner join mob m
         on l.max_mob >= m.months_on_book
      group by l.origination_year, l.origination_quarter, m.months_on_book
   )

   select
      v.origination_year
      , v.origination_quarter
      , v.months_on_book
      , c.cohort_loans
      , v.eligible_loans
      , v.cum_dlq60_loans
      , v.cum_dlq60_loans / v.eligible_loans as cum_dlq60_rate
      , c.release_id
   from curve v
   inner join cohort c
      on
         v.origination_year = c.origination_year
         and v.origination_quarter = c.origination_quarter;
   l_inserted := sql%rowcount;

   if l_inserted = 0 then
      raise_application_error(
         -20001, 'ads_vintage_dlq60_curve produced no rows: ' || in_release_id
      );
   end if;
end load_ads_vintage_dlq60_curve;
/
