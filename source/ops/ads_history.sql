-- Six non-segment ADS result histories. CTAS copies column types and order, but no rows.
-- Each history row belongs to one successful calculation; the registry also covers empty results.
-- CTAS with table star is required to preserve the current source column order.
-- noqa: disable=LT02,LT04,LT05,LT09,LT14,AL02,AM04
create table dw_ads_snapshot (
   calc_id number not null,
   output_table varchar2(40) not null,
   result_rows number not null,
   captured_at timestamp(6) with time zone default systimestamp not null,
   constraint dw_ads_snapshot_pk primary key (calc_id),
   constraint dw_ads_snapshot_calc_fk foreign key (calc_id)
      references dw_calculation (calc_id),
   constraint dw_ads_snapshot_rows_ck check (result_rows >= 0)
);

create table ads_vintage_dlq60_curve_hist as
select cast(null as number) calc_id, t.* from ads_vintage_dlq60_curve t where 1 = 0;
create index ads_vintage_hist_calc_ix on ads_vintage_dlq60_curve_hist (calc_id);
alter table ads_vintage_dlq60_curve_hist add constraint ads_vintage_hist_calc_fk
   foreign key (calc_id) references dw_ads_snapshot (calc_id);
alter table ads_vintage_dlq60_curve_hist modify calc_id not null;
alter table ads_vintage_dlq60_curve_hist add constraint ads_vintage_hist_uk
   unique (calc_id, release_id, origination_year,
      origination_quarter, months_on_book);

create table ads_dlq_transition_monthly_hist as
select cast(null as number) calc_id, t.* from ads_dlq_transition_monthly t where 1 = 0;
create index ads_transition_hist_calc_ix on ads_dlq_transition_monthly_hist (calc_id);
alter table ads_dlq_transition_monthly_hist add constraint ads_transition_hist_calc_fk
   foreign key (calc_id) references dw_ads_snapshot (calc_id);
alter table ads_dlq_transition_monthly_hist modify calc_id not null;
alter table ads_dlq_transition_monthly_hist add constraint ads_transition_hist_uk
   unique (calc_id, release_id, origination_year,
      monthly_reporting_period, from_state, to_state);

create table ads_modification_outcome_hist as
select cast(null as number) calc_id, t.* from ads_modification_outcome t where 1 = 0;
create index ads_mod_outcome_hist_calc_ix on ads_modification_outcome_hist (calc_id);
alter table ads_modification_outcome_hist add constraint ads_mod_outcome_hist_calc_fk
   foreign key (calc_id) references dw_ads_snapshot (calc_id);
alter table ads_modification_outcome_hist modify calc_id not null;
alter table ads_modification_outcome_hist add constraint ads_mod_outcome_hist_uk
   unique (calc_id, release_id, origination_year,
      first_mod_year, before_mod_group);

create table ads_release_diff_summary_hist as
select cast(null as number) calc_id, t.* from ads_release_diff_summary t where 1 = 0;
create index ads_diff_summary_hist_calc_ix on ads_release_diff_summary_hist (calc_id);
alter table ads_release_diff_summary_hist add constraint ads_diff_summary_hist_calc_fk
   foreign key (calc_id) references dw_ads_snapshot (calc_id);
alter table ads_release_diff_summary_hist modify calc_id not null;
alter table ads_release_diff_summary_hist add constraint ads_diff_summary_hist_uk
   unique (calc_id, old_release_id, new_release_id,
      source_table, source_column, change_type);

create table ads_release_diff_detail_hist as
select cast(null as number) calc_id, t.* from ads_release_diff_detail t where 1 = 0;
create index ads_diff_detail_hist_calc_ix on ads_release_diff_detail_hist (calc_id);
alter table ads_release_diff_detail_hist add constraint ads_diff_detail_hist_calc_fk
   foreign key (calc_id) references dw_ads_snapshot (calc_id);
alter table ads_release_diff_detail_hist modify calc_id not null;

create table ads_review_case_monthly_hist as
select cast(null as number) calc_id, t.* from ads_review_case_monthly t where 1 = 0;
create index ads_review_hist_calc_ix on ads_review_case_monthly_hist (calc_id);
alter table ads_review_case_monthly_hist add constraint ads_review_hist_calc_fk
   foreign key (calc_id) references dw_ads_snapshot (calc_id);
alter table ads_review_case_monthly_hist modify calc_id not null;
alter table ads_review_case_monthly_hist add constraint ads_review_hist_uk
   unique (calc_id, opened_month, data_source, rule_code, current_status);
