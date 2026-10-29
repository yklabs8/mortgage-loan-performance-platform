-- ads_vintage_dlq60_segment.sql
-- Ads vintage dlq60 segment. See docs/metric_definitions.md for analytical definitions.
create table ads_vintage_dlq60_segment (
   origination_year number(4) not null
   , origination_quarter number(1) not null
   , months_on_book number not null
   , segment_type varchar2(20) not null
   , segment_value varchar2(40) not null
   , cohort_loans number not null
   , eligible_loans number not null
   , cum_dlq60_loans number not null
   , cum_dlq60_rate number
   , release_id varchar2(10) not null
   , constraint ads_vintage_dlq60_segment_pk primary key (
      release_id, origination_year, origination_quarter
      , months_on_book, segment_type, segment_value
   )
);

-- noqa: disable=LT05
comment on table ads_vintage_dlq60_segment is 'Cumulative 60+ curves separately grouped by each attribute; group numerator divided by group denominator. Metric definitions sections 4 and 9.1.';
comment on column ads_vintage_dlq60_segment.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_vintage_dlq60_segment.origination_quarter is 'Origination quarter (User Guide p.7)';
comment on column ads_vintage_dlq60_segment.months_on_book is 'Months on book; metric definitions section 2';
comment on column ads_vintage_dlq60_segment.segment_type is 'One grouping attribute; metric definitions section 9.1';
comment on column ads_vintage_dlq60_segment.segment_value is 'Attribute group value; missing values become UNKNOWN';
comment on column ads_vintage_dlq60_segment.cohort_loans is 'All loans in the group and origination quarter';
comment on column ads_vintage_dlq60_segment.eligible_loans is 'Group loans eligible to reach this MOB by the data cutoff';
comment on column ads_vintage_dlq60_segment.cum_dlq60_loans is 'Group loans whose first 60+ MOB is no later than this MOB';
comment on column ads_vintage_dlq60_segment.cum_dlq60_rate is 'Group cumulative 60+ count / eligible count; NULL for zero denominator';
comment on column ads_vintage_dlq60_segment.release_id is 'Source data release';
-- noqa: enable=LT05
