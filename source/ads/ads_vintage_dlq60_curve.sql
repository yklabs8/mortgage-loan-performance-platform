-- ads_vintage_dlq60_curve.sql
-- Ads vintage dlq60 curve. See docs/metric_definitions.md for analytical definitions.
create table ads_vintage_dlq60_curve (
   origination_year number(4) not null
   , origination_quarter number(1) not null
   , months_on_book number not null
   , cohort_loans number not null
   , eligible_loans number not null
   , cum_dlq60_loans number not null
   , cum_dlq60_rate number not null
   , release_id varchar2(10) not null
   , constraint ads_vintage_dlq60_curve_pk primary key (
      release_id, origination_year, origination_quarter, months_on_book
   )
);

-- noqa: disable=LT05
comment on table ads_vintage_dlq60_curve is 'ADS: cumulative 60+ curve by release, origination year and quarter, and MOB. Input: dws_perf_loan_td. Metric definitions section 4.';
comment on column ads_vintage_dlq60_curve.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_vintage_dlq60_curve.origination_quarter is 'Origination quarter (User Guide p.7). Quarterly cohorts reduce tail-composition changes.';
comment on column ads_vintage_dlq60_curve.months_on_book is 'Months on book; metric definitions section 2';
comment on column ads_vintage_dlq60_curve.cohort_loans is 'Total loans in this origination quarter';
comment on column ads_vintage_dlq60_curve.eligible_loans is 'Denominator: loans whose first payment month allows reaching this MOB by the release cutoff; includes loans prepaid earlier';
comment on column ads_vintage_dlq60_curve.cum_dlq60_loans is 'Numerator: eligible loans whose first 60+ MOB is no later than this MOB';
comment on column ads_vintage_dlq60_curve.cum_dlq60_rate is 'Cumulative 60+ rate = cum_dlq60_loans / eligible_loans';
comment on column ads_vintage_dlq60_curve.release_id is 'Freddie data release, e.g. R47';
-- noqa: enable=LT05
