-- ads_modification_outcome.sql
-- Ads modification outcome. See docs/metric_definitions.md for analytical definitions.
create table ads_modification_outcome (
   origination_year number(4) not null
   , first_mod_year number(4) not null
   , before_mod_group varchar2(10) not null
   , modified_loans number not null
   , observable_12m_loans number not null
   , redefault_12m_loans number not null
   , current_12m_loans number not null
   , prepaid_12m_loans number not null
   , redefault_12m_rate number
   , current_12m_rate number
   , release_id varchar2(10) not null
   , constraint ads_modification_outcome_pk primary key (
      release_id
      , origination_year
      , first_mod_year
      , before_mod_group
   )
);

-- noqa: disable=LT05
comment on table ads_modification_outcome is 'ADS: one row per release, origination year, first modification year, and pre-modification 60+ status. Derived from dws_mod_loan_td; metric definitions section 6.';
comment on column ads_modification_outcome.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_modification_outcome.first_mod_year is 'Year of first modification';
comment on column ads_modification_outcome.before_mod_group is 'Prior 12-month status: DLQ60, NOT_DLQ60, or NO_PRIOR (no prior records)';
comment on column ads_modification_outcome.modified_loans is 'Modified loans';
comment on column ads_modification_outcome.observable_12m_loans is 'Loans observable for 12 months after modification or exited earlier; rate denominator';
comment on column ads_modification_outcome.redefault_12m_loans is 'Observable loans returning to 60+ in months 1-12 after modification';
comment on column ads_modification_outcome.current_12m_loans is 'Observable loans current (C) in month 12 after modification';
comment on column ads_modification_outcome.prepaid_12m_loans is 'Observable loans prepaid or matured within 12 months after modification';
comment on column ads_modification_outcome.redefault_12m_rate is '12-month redefault rate: redefault_12m_loans / observable_12m_loans; NULL for zero denominator';
comment on column ads_modification_outcome.current_12m_rate is 'Month-12 current rate: current_12m_loans / observable_12m_loans; NULL for zero denominator';
comment on column ads_modification_outcome.release_id is 'Freddie data release, e.g. R47';
-- noqa: enable=LT05
