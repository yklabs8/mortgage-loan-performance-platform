-- ads_dlq_transition_segment.sql
-- Ads dlq transition segment. See docs/metric_definitions.md for analytical definitions.
create table ads_dlq_transition_segment (
   origination_year number(4) not null
   , monthly_reporting_period date not null
   , from_state varchar2(10) not null
   , from_state_order number not null
   , to_state varchar2(10) not null
   , to_state_order number not null
   , segment_type varchar2(20) not null
   , segment_value varchar2(40) not null
   , loan_count number not null
   , release_id varchar2(10) not null
   , constraint ads_dlq_transition_segment_pk primary key (
      release_id, origination_year, monthly_reporting_period
      , from_state, to_state, segment_type, segment_value
   )
);

-- noqa: disable=LT05
comment on table ads_dlq_transition_segment is 'Adjacent-month transitions separately grouped by each loan attribute; metric definitions sections 5 and 9.1';
comment on column ads_dlq_transition_segment.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_dlq_transition_segment.monthly_reporting_period is 'Current reporting month';
comment on column ads_dlq_transition_segment.from_state is 'Prior state; categories follow metric definitions section 5';
comment on column ads_dlq_transition_segment.from_state_order is 'Prior-state display order';
comment on column ads_dlq_transition_segment.to_state is 'Current state or exit state; metric definitions section 5';
comment on column ads_dlq_transition_segment.to_state_order is 'Current-state display order';
comment on column ads_dlq_transition_segment.segment_type is 'One grouping attribute; metric definitions section 9.1';
comment on column ads_dlq_transition_segment.segment_value is 'Attribute group value; missing values become UNKNOWN';
comment on column ads_dlq_transition_segment.loan_count is 'Adjacent-month loan-transition count in this group';
comment on column ads_dlq_transition_segment.release_id is 'Source data release';
-- noqa: enable=LT05
