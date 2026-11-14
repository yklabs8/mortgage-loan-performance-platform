-- Name: dwd_review_case.sql
-- Purpose: create the review case fact table dwd_review_case: an accumulating snapshot fact table with one row per case;
--          each step a case takes (assign, start review, decide, close) fills the matching date; merged incrementally by timestamp in cdc_review
-- Requires: dim_date, dim_review_rule, dim_loan_key_map, dim_case_status, dim_review_user_identity exist
-- Called by: scripts/run_sql.sh source/dwd/dwd_review_case.sql (run once)

create table dwd_review_case (
   case_id number not null
   , case_number varchar2(20) not null
   , candidate_id number not null
   , rule_version_key number not null
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , loan_durable_key number not null
   , reporting_month date not null
   , reporting_date_key number(8) not null
   , source_release_id varchar2(10) not null
   , current_status varchar2(20) not null
   , opened_by_user_id number not null
   , current_assignee_user_id number
   , opened_at timestamp(6) not null
   , opened_date_key number(8) not null
   , first_assigned_at timestamp(6)
   , first_in_review_at timestamp(6)
   , last_decided_at timestamp(6)
   , last_decision_type varchar2(20)
   , closed_at timestamp(6)
   , closed_date_key number(8)
   , was_escalated varchar2(1) not null
   , was_reopened varchar2(1) default 'N' not null
   , status_change_count number not null
   , annotation_count number not null
   , source_updated_at timestamp(6) not null
   , constraint dwd_review_case_pk primary key (case_id)
   , constraint dwd_review_case_escalated_ck check (was_escalated in ('Y', 'N'))
   , constraint dwd_review_case_reopened_ck check (was_reopened in ('Y', 'N'))
   , constraint drc_drr_fk foreign key (rule_version_key)
   references dim_review_rule (rule_version_key)
   , constraint drc_dlkm_fk foreign key (loan_durable_key)
   references dim_loan_key_map (loan_durable_key)
   , constraint drc_dd_reporting_fk foreign key (reporting_date_key)
   references dim_date (date_key)
   , constraint drc_dd_opened_fk foreign key (opened_date_key)
   references dim_date (date_key)
   , constraint drc_dd_closed_fk foreign key (closed_date_key)
   references dim_date (date_key)
   , constraint drc_dcs_fk foreign key (current_status)
   references dim_case_status (status_code)
   , constraint drc_dru_opener_fk foreign key (opened_by_user_id)
   references dim_review_user_identity (user_id)
   , constraint drc_dru_assignee_fk foreign key (current_assignee_user_id)
   references dim_review_user_identity (user_id)
);

-- noqa: disable=LT05
comment on table dwd_review_case is 'DWD: review case, accumulating snapshot fact table, one row per case. Source: OLTP risk_review_case with its assignments, notes, status history, and decisions; extracted incrementally by updated_at (cdc_review)';
comment on column dwd_review_case.case_id is 'OLTP case ID (business key)';
comment on column dwd_review_case.case_number is 'Human-readable case number such as RRC-000001';
comment on column dwd_review_case.candidate_id is 'OLTP candidate ID';
comment on column dwd_review_case.rule_version_key is 'Rule version that selected the candidate (surrogate key of dim_review_rule, SCD2)';
comment on column dwd_review_case.data_source is 'Agency: FRE';
comment on column dwd_review_case.loan_identifier is 'The agency''s own loan number';
comment on column dwd_review_case.loan_durable_key is 'Durable loan key (dim_loan_key_map): stable across releases';
comment on column dwd_review_case.reporting_month is 'Month that triggered the review';
comment on column dwd_review_case.reporting_date_key is 'Date key of the triggering month (dim_date)';
comment on column dwd_review_case.source_release_id is 'Warehouse release used for selection';
comment on column dwd_review_case.current_status is 'Current status (dim_case_status)';
comment on column dwd_review_case.opened_by_user_id is 'user_id of the person who opened the case; the foreign key points to the stable identity table, historical attributes are looked up by time in dim_review_user';
comment on column dwd_review_case.current_assignee_user_id is 'Latest assignee; empty if not yet assigned';
comment on column dwd_review_case.opened_at is 'Time the case was opened';
comment on column dwd_review_case.opened_date_key is 'Date key of opening (dim_date)';
comment on column dwd_review_case.first_assigned_at is 'Time of the first assignment';
comment on column dwd_review_case.first_in_review_at is 'Time the case first entered IN_REVIEW';
comment on column dwd_review_case.last_decided_at is 'Time of the latest manager decision';
comment on column dwd_review_case.last_decision_type is 'Latest decision: CLOSE / ESCALATE / REOPEN';
comment on column dwd_review_case.closed_at is 'Close time (written by the OLTP trigger on entering a terminal status)';
comment on column dwd_review_case.closed_date_key is 'Date key of closing; empty if not closed';
comment on column dwd_review_case.was_escalated is 'Ever escalated: Y / N';
comment on column dwd_review_case.was_reopened is 'Ever reopened from CLOSED: Y / N; the status history keeps every close and reopen';
comment on column dwd_review_case.status_change_count is 'Number of status changes (including opening)';
comment on column dwd_review_case.annotation_count is 'Number of notes';
comment on column dwd_review_case.source_updated_at is 'Last modification time of the case in OLTP (what incremental extraction looks at)';
-- noqa: enable=LT05
