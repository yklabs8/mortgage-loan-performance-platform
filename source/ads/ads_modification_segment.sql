-- ads_modification_segment.sql
-- Ads modification segment. See docs/metric_definitions.md for analytical definitions.
create table ads_modification_segment (
   origination_year number(4) not null
   , first_mod_year number(4) not null
   , before_mod_group varchar2(10) not null
   , segment_type varchar2(20) not null
   , segment_value varchar2(40) not null
   , modified_loans number not null
   , observable_12m_loans number not null
   , redefault_12m_loans number not null
   , current_12m_loans number not null
   , prepaid_12m_loans number not null
   , redefault_12m_rate number
   , current_12m_rate number
   , release_id varchar2(10) not null
   , constraint ads_modification_segment_pk primary key (
      release_id, origination_year, first_mod_year, before_mod_group
      , segment_type, segment_value
   )
);

-- noqa: disable=LT05
comment on table ads_modification_segment is 'First-modification 12-month outcomes separately grouped by each attribute; metric definitions sections 6 and 9.1';
comment on column ads_modification_segment.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_modification_segment.first_mod_year is 'First modification year (User Guide p.11)';
comment on column ads_modification_segment.before_mod_group is 'Any 60+ in the prior 12 months; metric definitions section 6';
comment on column ads_modification_segment.segment_type is 'One grouping attribute; metric definitions section 9.1';
comment on column ads_modification_segment.segment_value is 'Attribute group value; missing values become UNKNOWN';
comment on column ads_modification_segment.modified_loans is 'Loans with a first modification';
comment on column ads_modification_segment.observable_12m_loans is 'Loans observable through month 12 or an earlier exit';
comment on column ads_modification_segment.redefault_12m_loans is 'Observable loans with 60+ in post-modification months 1-12';
comment on column ads_modification_segment.current_12m_loans is 'Observable loans current in month 12';
comment on column ads_modification_segment.prepaid_12m_loans is 'Observable loans prepaid within 12 months';
comment on column ads_modification_segment.redefault_12m_rate is 'Group redefault count divided by group observable count';
comment on column ads_modification_segment.current_12m_rate is 'Group current count divided by group observable count';
comment on column ads_modification_segment.release_id is 'Source data release';
-- noqa: enable=LT05
