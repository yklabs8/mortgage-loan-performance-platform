-- dim_delinquency_status.sql
-- Dim delinquency status. See docs/metric_definitions.md for analytical definitions.
create table dim_delinquency_status (
   status_code varchar2(3) not null
   , dlq_state varchar2(10) not null
   , dlq_state_order number not null
   , is_dlq60 varchar2(1) not null
   , constraint dim_delinquency_status_pk primary key (status_code)
   , constraint dim_delinquency_status_dlq60_ck check (is_dlq60 in ('Y', 'N'))
);

-- noqa: disable=LT05
comment on table dim_delinquency_status is 'DIM: one row per delinquency status (00-99, RA, XX). Source meanings: User Guide p.10. State bands and 60+ classification: docs/metric_definitions.md sections 1 and 5.';
comment on column dim_delinquency_status.status_code is 'Delinquency status code; foreign key target for the monthly fact';
comment on column dim_delinquency_status.dlq_state is 'State: C (current or under 30 days), 30, 60, 90, 120+, REO, or UNK';
comment on column dim_delinquency_status.dlq_state_order is 'State severity order: C=0 through 120+=4, REO=5, UNK=9';
comment on column dim_delinquency_status.is_dlq60 is '60+ flag: Y for 02-99 and RA; N for XX. See metric definitions section 1.';
-- noqa: enable=LT05
