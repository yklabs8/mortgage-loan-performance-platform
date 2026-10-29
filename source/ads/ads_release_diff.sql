-- ads_release_diff.sql
-- Ads release diff. See docs/metric_definitions.md for analytical definitions.
create table ads_release_diff_summary (
   old_release_id varchar2(10) not null
   , new_release_id varchar2(10) not null
   , source_table varchar2(30) not null
   , source_column varchar2(128) not null
   , change_type varchar2(40) not null
   , affected_rows number not null
   , constraint ads_release_diff_summary_pk primary key (
      old_release_id, new_release_id, source_table, source_column, change_type
   )
);

create table ads_release_diff_detail (
   old_release_id varchar2(10) not null
   , new_release_id varchar2(10) not null
   , source_table varchar2(30) not null
   , loan_identifier varchar2(12) not null
   , monthly_reporting_period date
   , source_column varchar2(128) not null
   , old_value varchar2(100)
   , new_value varchar2(100)
);

-- noqa: disable=LT05
comment on table ads_release_diff_summary is 'ADS: release differences after layout normalization. Count changed values per column, treating two NULLs as equal, plus rows present in only one release.';
comment on column ads_release_diff_summary.change_type is 'VALUE_CHANGED / OLD_ONLY / NEW_ONLY_WITHIN_OLD_RANGE / NEW_MONTHS';
comment on column ads_release_diff_summary.affected_rows is 'Affected rows: loans for dim_loan, loan-months for dwd_loan_monthly_perf';
comment on table ads_release_diff_detail is 'ADS: potential substantive correction detail. Known layout and disclosure changes (ELTV, cumulative modification costs, fields moved from origination to performance, new fields) remain in summary counts only.';
comment on column ads_release_diff_detail.monthly_reporting_period is 'Reporting month; NULL for loan-dimension differences';
comment on column ads_release_diff_detail.old_value is 'Old value after normalization, rendered as text';
comment on column ads_release_diff_detail.new_value is 'New value rendered as text';
-- noqa: enable=LT05
