-- ads_final_outcome_segment.sql
-- Ads final outcome segment. See docs/metric_definitions.md for analytical definitions.
create table ads_final_outcome_segment (
   origination_year number(4) not null
   , segment_type varchar2(20) not null
   , segment_value varchar2(40) not null
   , final_state varchar2(12) not null
   , loan_count number not null
   , release_id varchar2(10) not null
   , constraint ads_final_outcome_segment_pk primary key (
      release_id, origination_year, segment_type, segment_value, final_state
   )
);

-- noqa: disable=LT05
comment on table ads_final_outcome_segment is 'Final outcomes separately grouped by each loan attribute. ACTIVE if no exit; otherwise classified by agency and exit code. Metric definitions section 9.1.';
comment on column ads_final_outcome_segment.origination_year is 'Origination year (User Guide p.7)';
comment on column ads_final_outcome_segment.segment_type is 'One grouping attribute; metric definitions section 9.1';
comment on column ads_final_outcome_segment.segment_value is 'Attribute group value; missing values become UNKNOWN';
comment on column ads_final_outcome_segment.final_state is 'ACTIVE, PREPAID, LIQUIDATED, LOAN_SALE, or DEFECT; metric definitions section 5';
comment on column ads_final_outcome_segment.loan_count is 'Loans with this final outcome; each loan counted once';
comment on column ads_final_outcome_segment.release_id is 'Source data release';
-- noqa: enable=LT05
