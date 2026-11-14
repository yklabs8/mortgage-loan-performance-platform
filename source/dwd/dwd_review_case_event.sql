-- Name: dwd_review_case_event.sql
-- Purpose: create the review case status change fact table dwd_review_case_event: a transaction fact table with one row per status change (from OLTP case_status_history,
--          append-only), merged incrementally by changed_at in cdc_review
-- Requires: dim_date, dim_case_status, dim_review_user_identity exist
-- Called by: scripts/run_sql.sh source/dwd/dwd_review_case_event.sql (run once)

create table dwd_review_case_event (
   status_event_id number not null
   , case_id number not null
   , from_status varchar2(20)
   , to_status varchar2(20) not null
   , changed_by_user_id number
   , changed_at timestamp(6) not null
   , changed_date_key number(8) not null
   , constraint dwd_review_case_event_pk primary key (status_event_id)
   , constraint drce_dcs_from_fk foreign key (from_status)
   references dim_case_status (status_code)
   , constraint drce_dcs_to_fk foreign key (to_status)
   references dim_case_status (status_code)
   , constraint drce_dru_fk foreign key (changed_by_user_id)
   references dim_review_user_identity (user_id)
   , constraint drce_dd_fk foreign key (changed_date_key)
   references dim_date (date_key)
);

-- noqa: disable=LT05
comment on table dwd_review_case_event is 'DWD: review case status changes, transaction fact table, one row per change. Source: OLTP case_status_history; extracted incrementally by changed_at (cdc_review)';
comment on column dwd_review_case_event.status_event_id is 'OLTP status history ID (business key)';
comment on column dwd_review_case_event.case_id is 'OLTP case ID';
comment on column dwd_review_case_event.from_status is 'Previous status; empty when the case is opened';
comment on column dwd_review_case_event.to_status is 'New status';
comment on column dwd_review_case_event.changed_by_user_id is 'Who made the change';
comment on column dwd_review_case_event.changed_at is 'Change time';
comment on column dwd_review_case_event.changed_date_key is 'Date key of the change (dim_date)';
-- noqa: enable=LT05
