-- First warehouse path; source definitions and calculations are documented in docs/metric_definitions.md.

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
-- noqa: enable=LT05
