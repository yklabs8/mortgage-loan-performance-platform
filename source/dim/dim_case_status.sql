-- Name: dim_case_status.sql
-- Purpose: create the review case status dimension dim_case_status: one row per OLTP case_status (OPEN, ASSIGNED, IN_REVIEW, ESCALATED, CLOSED),
--          fully synced by cdc_review on every run (only 5 rows)
-- Called by: deployment scripts or manually
-- Called by: scripts/run_sql.sh source/dim/dim_case_status.sql (run once)

create table dim_case_status (
   status_code varchar2(20) not null
   , status_name varchar2(100) not null
   , is_terminal varchar2(1) not null
   , constraint dim_case_status_pk primary key (status_code)
   , constraint dim_case_status_is_terminal_ck check (is_terminal in ('Y', 'N'))
);

-- noqa: disable=LT05
comment on table dim_case_status is 'DIM: review case status, from OLTP case_status (review workflow star schema)';
comment on column dim_case_status.status_code is 'Status code';
comment on column dim_case_status.status_name is 'Status name';
comment on column dim_case_status.is_terminal is 'Terminal status: Y / N';
-- noqa: enable=LT05
