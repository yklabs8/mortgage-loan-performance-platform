-- Name: candidate_delivery.sql
-- Purpose: add the candidate source and pin case evidence; create the candidate delivery tables and the transactional stage area.
-- Requires: oltp_tables.sql; run once by loan_oltp through scripts/run_sql.sh.
-- Called by: candidate migration; a fresh install runs this file after oltp_tables.sql.
-- run_sql.sh already exits at the first SQL error.

alter table review_candidate add (
   candidate_source varchar2(6) default 'SAMPLE' not null
   , latest_evidence_id number
);
alter table review_candidate add constraint review_candidate_source_ck
check (candidate_source in ('SAMPLE', 'DW', 'TEST'));

create table review_candidate_delivery (
   delivery_id raw(16) not null
   , manifest_sha256 varchar2(64) not null
   , manifest_json clob not null
   , status varchar2(10) not null
   , error_message varchar2(4000)
   , created_at timestamp(6) default systimestamp not null
   , published_at timestamp(6)
   , constraint review_candidate_delivery_pk primary key (delivery_id)
   , constraint review_candidate_delivery_status_ck check (
      status in ('PREPARING', 'VALIDATED', 'PUBLISHED', 'FAILED')
   )
);

create table review_evidence (
   evidence_id number generated always as identity
   , candidate_id number not null
   , delivery_id raw(16) not null
   , rule_version_id number not null
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , reporting_month date not null
   , source_release_id varchar2(10)
   , rule_code varchar2(50)
   , version_no number
   , min_delinquency_status number
   , classic_fico number
   , original_upb number
   , original_loan_to_value_ltv number
   , original_interest_rate number
   , property_state varchar2(3)
   , origination_year number
   , first_payment_date date
   , current_loan_delinquency_status varchar2(3)
   , current_actual_upb number
   , current_interest_rate number
   , zero_balance_code varchar2(3)
   , zero_balance_effective_date date
   , modification_flag varchar2(3)
   , previous_delinquency_status varchar2(3)
   , previous_month_missing varchar2(5)
   , missing_months varchar2(200)
   , content_sha256 varchar2(64) not null
   , created_at timestamp(6) default systimestamp not null
   , constraint review_evidence_pk primary key (evidence_id)
   , constraint review_evidence_content_uk unique (candidate_id, content_sha256)
   , constraint review_evidence_candidate_uk unique (candidate_id, evidence_id)
   , constraint rev_rcd_fk foreign key (
      candidate_id
   ) references review_candidate (candidate_id)
   , constraint rev_delivery_fk foreign key (
      delivery_id
   ) references review_candidate_delivery (delivery_id)
);

create table review_evidence_month (
   evidence_id number not null
   , monthly_reporting_period date
   , current_loan_delinquency_status varchar2(3)
   , current_actual_upb number
   , current_interest_rate number
   , zero_balance_code varchar2(3)
   , zero_balance_effective_date date
   , modification_flag varchar2(3)
   , constraint review_evidence_month_pk primary key (
      evidence_id, monthly_reporting_period
   )
   , constraint rem_rev_fk foreign key (
      evidence_id
   ) references review_evidence (evidence_id)
);

alter table review_candidate add constraint rcd_rev_fk foreign key (
   candidate_id, latest_evidence_id
) references review_evidence (candidate_id, evidence_id);
alter table risk_review_case add evidence_id number;
alter table risk_review_case add constraint rrc_rev_fk
foreign key (candidate_id, evidence_id)
references review_evidence (candidate_id, evidence_id);
create index risk_review_case_evidence_idx on risk_review_case (
   candidate_id, evidence_id
);
create index review_evidence_delivery_idx on review_evidence (delivery_id);

create global temporary table review_candidate_stage (
   rule_version_id number not null
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , reporting_month date not null
   , delinquency_status varchar2(3)
   , source_release_id varchar2(10)
   , constraint review_candidate_stage_pk primary key (
      rule_version_id, data_source, loan_identifier, reporting_month
   )
) on commit delete rows;

create global temporary table review_evidence_stage (
   rule_version_id number not null
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , reporting_month date not null
   , source_release_id varchar2(10)
   , rule_code varchar2(50)
   , version_no number
   , min_delinquency_status number
   , classic_fico number
   , original_upb number
   , original_loan_to_value_ltv number
   , original_interest_rate number
   , property_state varchar2(3)
   , origination_year number
   , first_payment_date date
   , current_loan_delinquency_status varchar2(3)
   , current_actual_upb number
   , current_interest_rate number
   , zero_balance_code varchar2(3)
   , zero_balance_effective_date date
   , modification_flag varchar2(3)
   , previous_delinquency_status varchar2(3)
   , previous_month_missing varchar2(5)
   , missing_months varchar2(200)
   , content_sha256 varchar2(64)
   , constraint review_evidence_stage_pk primary key (
      rule_version_id, data_source, loan_identifier, reporting_month
   )
) on commit delete rows;

create global temporary table review_evidence_month_stage (
   rule_version_id number not null
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , reporting_month date not null
   , monthly_reporting_period date
   , current_loan_delinquency_status varchar2(3)
   , current_actual_upb number
   , current_interest_rate number
   , zero_balance_code varchar2(3)
   , zero_balance_effective_date date
   , modification_flag varchar2(3)
   , constraint review_evidence_month_stage_pk primary key (
      rule_version_id
      , data_source
      , loan_identifier
      , reporting_month
      , monthly_reporting_period
   )
) on commit delete rows;

create table review_candidate_import_lock (
   lock_id number not null
   , constraint review_candidate_import_lock_pk primary key (lock_id)
   , constraint review_candidate_import_lock_id_ck check (lock_id = 1)
);
insert into review_candidate_import_lock (lock_id) values (1);
commit;

-- Column comments spell out the contract column names and may exceed 80 columns.
-- noqa: disable=LT05
comment on table review_candidate_delivery is 'Candidate delivery: review_candidate_delivery; column order in python/candidate_import.py';
comment on column review_candidate_delivery.delivery_id is 'Candidate delivery: delivery_id';
comment on column review_candidate_delivery.manifest_sha256 is 'Candidate delivery: manifest_sha256';
comment on column review_candidate_delivery.manifest_json is 'Candidate delivery: manifest_json';
comment on column review_candidate_delivery.status is 'Candidate delivery: status';
comment on column review_candidate_delivery.error_message is 'Candidate delivery: error_message';
comment on column review_candidate_delivery.created_at is 'Candidate delivery: created_at';
comment on column review_candidate_delivery.published_at is 'Candidate delivery: published_at';
comment on table review_evidence is 'Candidate delivery: review_evidence; column order in python/candidate_import.py';
comment on column review_evidence.evidence_id is 'Candidate delivery: evidence_id';
comment on column review_evidence.candidate_id is 'Candidate delivery: candidate_id';
comment on column review_evidence.delivery_id is 'Candidate delivery: delivery_id';
comment on column review_evidence.rule_version_id is 'Candidate delivery: rule_version_id';
comment on column review_evidence.data_source is 'Candidate delivery: data_source';
comment on column review_evidence.loan_identifier is 'Candidate delivery: loan_identifier';
comment on column review_evidence.reporting_month is 'Candidate delivery: reporting_month';
comment on column review_evidence.source_release_id is 'Candidate delivery: source_release_id';
comment on column review_evidence.rule_code is 'Candidate delivery: rule_code';
comment on column review_evidence.version_no is 'Candidate delivery: version_no';
comment on column review_evidence.min_delinquency_status is 'Candidate delivery: min_delinquency_status';
comment on column review_evidence.classic_fico is 'Candidate delivery: classic_fico';
comment on column review_evidence.original_upb is 'Candidate delivery: original_upb';
comment on column review_evidence.original_loan_to_value_ltv is 'Candidate delivery: original_loan_to_value_ltv';
comment on column review_evidence.original_interest_rate is 'Candidate delivery: original_interest_rate';
comment on column review_evidence.property_state is 'Candidate delivery: property_state';
comment on column review_evidence.origination_year is 'Candidate delivery: origination_year';
comment on column review_evidence.first_payment_date is 'Candidate delivery: first_payment_date';
comment on column review_evidence.current_loan_delinquency_status is 'Candidate delivery: current_loan_delinquency_status';
comment on column review_evidence.current_actual_upb is 'Candidate delivery: current_actual_upb';
comment on column review_evidence.current_interest_rate is 'Candidate delivery: current_interest_rate';
comment on column review_evidence.zero_balance_code is 'Candidate delivery: zero_balance_code';
comment on column review_evidence.zero_balance_effective_date is 'Candidate delivery: zero_balance_effective_date';
comment on column review_evidence.modification_flag is 'Candidate delivery: modification_flag';
comment on column review_evidence.previous_delinquency_status is 'Candidate delivery: previous_delinquency_status';
comment on column review_evidence.previous_month_missing is 'Candidate delivery: previous_month_missing';
comment on column review_evidence.missing_months is 'Candidate delivery: missing_months';
comment on column review_evidence.content_sha256 is 'Candidate delivery: content_sha256';
comment on column review_evidence.created_at is 'Candidate delivery: created_at';
comment on table review_evidence_month is 'Candidate delivery: review_evidence_month; column order in python/candidate_import.py';
comment on column review_evidence_month.evidence_id is 'Candidate delivery: evidence_id';
comment on column review_evidence_month.monthly_reporting_period is 'Candidate delivery: monthly_reporting_period';
comment on column review_evidence_month.current_loan_delinquency_status is 'Candidate delivery: current_loan_delinquency_status';
comment on column review_evidence_month.current_actual_upb is 'Candidate delivery: current_actual_upb';
comment on column review_evidence_month.current_interest_rate is 'Candidate delivery: current_interest_rate';
comment on column review_evidence_month.zero_balance_code is 'Candidate delivery: zero_balance_code';
comment on column review_evidence_month.zero_balance_effective_date is 'Candidate delivery: zero_balance_effective_date';
comment on column review_evidence_month.modification_flag is 'Candidate delivery: modification_flag';
comment on table review_candidate_stage is 'Candidate delivery: review_candidate_stage; column order in python/candidate_import.py';
comment on column review_candidate_stage.rule_version_id is 'Candidate delivery: rule_version_id';
comment on column review_candidate_stage.data_source is 'Candidate delivery: data_source';
comment on column review_candidate_stage.loan_identifier is 'Candidate delivery: loan_identifier';
comment on column review_candidate_stage.reporting_month is 'Candidate delivery: reporting_month';
comment on column review_candidate_stage.delinquency_status is 'Candidate delivery: delinquency_status';
comment on column review_candidate_stage.source_release_id is 'Candidate delivery: source_release_id';
comment on table review_evidence_stage is 'Candidate delivery: review_evidence_stage; column order in python/candidate_import.py';
comment on column review_evidence_stage.rule_version_id is 'Candidate delivery: rule_version_id';
comment on column review_evidence_stage.data_source is 'Candidate delivery: data_source';
comment on column review_evidence_stage.loan_identifier is 'Candidate delivery: loan_identifier';
comment on column review_evidence_stage.reporting_month is 'Candidate delivery: reporting_month';
comment on column review_evidence_stage.source_release_id is 'Candidate delivery: source_release_id';
comment on column review_evidence_stage.rule_code is 'Candidate delivery: rule_code';
comment on column review_evidence_stage.version_no is 'Candidate delivery: version_no';
comment on column review_evidence_stage.min_delinquency_status is 'Candidate delivery: min_delinquency_status';
comment on column review_evidence_stage.classic_fico is 'Candidate delivery: classic_fico';
comment on column review_evidence_stage.original_upb is 'Candidate delivery: original_upb';
comment on column review_evidence_stage.original_loan_to_value_ltv is 'Candidate delivery: original_loan_to_value_ltv';
comment on column review_evidence_stage.original_interest_rate is 'Candidate delivery: original_interest_rate';
comment on column review_evidence_stage.property_state is 'Candidate delivery: property_state';
comment on column review_evidence_stage.origination_year is 'Candidate delivery: origination_year';
comment on column review_evidence_stage.first_payment_date is 'Candidate delivery: first_payment_date';
comment on column review_evidence_stage.current_loan_delinquency_status is 'Candidate delivery: current_loan_delinquency_status';
comment on column review_evidence_stage.current_actual_upb is 'Candidate delivery: current_actual_upb';
comment on column review_evidence_stage.current_interest_rate is 'Candidate delivery: current_interest_rate';
comment on column review_evidence_stage.zero_balance_code is 'Candidate delivery: zero_balance_code';
comment on column review_evidence_stage.zero_balance_effective_date is 'Candidate delivery: zero_balance_effective_date';
comment on column review_evidence_stage.modification_flag is 'Candidate delivery: modification_flag';
comment on column review_evidence_stage.previous_delinquency_status is 'Candidate delivery: previous_delinquency_status';
comment on column review_evidence_stage.previous_month_missing is 'Candidate delivery: previous_month_missing';
comment on column review_evidence_stage.missing_months is 'Candidate delivery: missing_months';
comment on column review_evidence_stage.content_sha256 is 'Candidate delivery: content_sha256';
comment on table review_evidence_month_stage is 'Candidate delivery: review_evidence_month_stage; column order in python/candidate_import.py';
comment on column review_evidence_month_stage.rule_version_id is 'Candidate delivery: rule_version_id';
comment on column review_evidence_month_stage.data_source is 'Candidate delivery: data_source';
comment on column review_evidence_month_stage.loan_identifier is 'Candidate delivery: loan_identifier';
comment on column review_evidence_month_stage.reporting_month is 'Candidate delivery: reporting_month';
comment on column review_evidence_month_stage.monthly_reporting_period is 'Candidate delivery: monthly_reporting_period';
comment on column review_evidence_month_stage.current_loan_delinquency_status is 'Candidate delivery: current_loan_delinquency_status';
comment on column review_evidence_month_stage.current_actual_upb is 'Candidate delivery: current_actual_upb';
comment on column review_evidence_month_stage.current_interest_rate is 'Candidate delivery: current_interest_rate';
comment on column review_evidence_month_stage.zero_balance_code is 'Candidate delivery: zero_balance_code';
comment on column review_evidence_month_stage.zero_balance_effective_date is 'Candidate delivery: zero_balance_effective_date';
comment on column review_evidence_month_stage.modification_flag is 'Candidate delivery: modification_flag';
comment on table review_candidate_import_lock is 'Candidate delivery: review_candidate_import_lock; column order in python/candidate_import.py';
comment on column review_candidate_import_lock.lock_id is 'Candidate delivery: lock_id';
comment on column review_candidate.candidate_source is 'Source: SAMPLE reference interface review_api.generate_candidates, DW published by candidate_publish with evidence, TEST test fixture';
comment on column review_candidate.latest_evidence_id is 'Latest published evidence version; identical content reuses the existing version';
comment on column risk_review_case.evidence_id is 'Evidence version pinned when the case was opened; later deliveries do not overwrite it';
-- noqa: enable=LT05
