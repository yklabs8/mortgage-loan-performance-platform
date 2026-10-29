-- ads_dlq_transition_monthly.sql
-- Ads dlq transition monthly. See docs/metric_definitions.md for analytical definitions.
create table ads_dlq_transition_monthly (
   origination_year number(4) not null
   , monthly_reporting_period date not null
   , from_state varchar2(10) not null
   , from_state_order number not null
   , to_state varchar2(10) not null
   , to_state_order number not null
   , loan_count number not null
   , release_id varchar2(10) not null
   , constraint ads_dlq_transition_monthly_pk primary key (
      release_id
      , origination_year
      , monthly_reporting_period
      , from_state
      , to_state
   )
);

-- noqa: disable=LT05
comment on table ads_dlq_transition_monthly is 'ADS: one row per release, origination year, reporting month, prior state, and current state. Roll rates use monthly facts and code dimensions; see metric definitions section 5.';
comment on column ads_dlq_transition_monthly.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_dlq_transition_monthly.monthly_reporting_period is 'Current reporting month, the transition destination';
comment on column ads_dlq_transition_monthly.from_state is 'Prior state: C, 30, 60, 90, 120+, REO, or UNK';
comment on column ads_dlq_transition_monthly.from_state_order is 'Prior-state display order for the transition matrix';
comment on column ads_dlq_transition_monthly.to_state is 'Current state or, for an exit this month, PREPAID, LIQUIDATED, LOAN_SALE, or DEFECT';
comment on column ads_dlq_transition_monthly.to_state_order is 'Current-state display order for the transition matrix';
comment on column ads_dlq_transition_monthly.loan_count is 'Transition count; includes only records exactly one calendar month apart';
comment on column ads_dlq_transition_monthly.release_id is 'Freddie data release, e.g. R47';
-- noqa: enable=LT05
