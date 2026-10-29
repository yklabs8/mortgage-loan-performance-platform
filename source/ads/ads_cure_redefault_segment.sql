-- ads_cure_redefault_segment.sql
-- Ads cure redefault segment. See docs/metric_definitions.md for analytical definitions.
create table ads_cure_redefault_segment (
   origination_year number(4) not null
   , segment_type varchar2(20) not null
   , segment_value varchar2(40) not null
   , dlq60_loans number not null
   , cured_loans number not null
   , cure_events number not null
   , redefault_loans number not null
   , cure_rate number
   , release_id varchar2(10) not null
   , constraint ads_cure_redefault_segment_pk primary key (
      release_id, origination_year, segment_type, segment_value
   )
   , constraint ads_cure_redefault_segment_count_ck check (
      dlq60_loans >= cured_loans
      and cure_events >= cured_loans
      and cured_loans >= redefault_loans
   )
);

-- noqa: disable=LT05
comment on table ads_cure_redefault_segment is 'Cure requires three consecutive calendar months current after 60+. Each loan attribute is grouped separately. Metric definitions section 9.1.';
comment on column ads_cure_redefault_segment.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_cure_redefault_segment.segment_type is 'One of nine separately grouped loan attributes';
comment on column ads_cure_redefault_segment.segment_value is 'Attribute group value; missing values become UNKNOWN';
comment on column ads_cure_redefault_segment.dlq60_loans is 'Loans ever 60+, each counted once';
comment on column ads_cure_redefault_segment.cured_loans is 'Loans with at least one cure, each counted once';
comment on column ads_cure_redefault_segment.cure_events is 'Cure events; repeated cures of one loan count separately';
comment on column ads_cure_redefault_segment.redefault_loans is 'Loans returning to 60+ after cure, each counted once';
comment on column ads_cure_redefault_segment.cure_rate is 'cured_loans / dlq60_loans; NULL for zero denominator';
comment on column ads_cure_redefault_segment.release_id is 'Source data release';
-- noqa: enable=LT05
