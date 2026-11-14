-- Name: ads_review_case_monthly.sql
-- Purpose: create the ADS monthly review case report: one row per opening month, agency, rule, and current status,
--          with case counts, escalated cases, closed cases, and days to close
-- Called by: deployment scripts or manually
-- Called by: scripts/run_sql.sh source/ads/ads_review_case_monthly.sql (run once)

create table ads_review_case_monthly (
   opened_month date not null
   , data_source varchar2(3) not null
   , rule_code varchar2(30) not null
   , current_status varchar2(20) not null
   , case_count number not null
   , escalated_count number not null
   , reopened_count number default 0 not null
   , closed_count number not null
   , total_days_to_close number not null
   , refreshed_at timestamp(6) not null
   , constraint ads_review_case_monthly_pk primary key (
      opened_month
      , data_source
      , rule_code
      , current_status
   )
);

-- Comment lines exceed 80 characters; line-length checks are off for this block (platform convention)
-- noqa: disable=LT05
comment on table ads_review_case_monthly is 'ADS: monthly review case report. One row per opening month, agency, rule, and current status; from dwd_review_case (accumulating snapshot), dim_review_rule, and dim_case_status; fully recomputed after each incremental extraction (source/dwd/run_cdc_review.sql). No release_id: review cases come from OLTP and belong to no Freddie Mac release';
comment on column ads_review_case_monthly.opened_month is 'Opening month (first day of the month)';
comment on column ads_review_case_monthly.data_source is 'Agency: FRE = Freddie Mac';
comment on column ads_review_case_monthly.rule_code is 'Rule that selected the candidate (all versions)';
comment on column ads_review_case_monthly.current_status is 'Current case status (dim_case_status)';
comment on column ads_review_case_monthly.case_count is 'Number of cases';
comment on column ads_review_case_monthly.escalated_count is 'Cases ever escalated (including those closed after escalation)';
comment on column ads_review_case_monthly.reopened_count is 'Cases ever reopened from CLOSED, regardless of current status';
comment on column ads_review_case_monthly.closed_count is 'Closed cases';
comment on column ads_review_case_monthly.total_days_to_close is 'Sum of days from opening to first close for currently closed cases; average days = sum(total_days_to_close) / sum(closed_count)';
comment on column ads_review_case_monthly.refreshed_at is 'When this row was recomputed';
-- noqa: enable=LT05
