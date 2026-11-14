-- Name: oltp_tables.sql
-- Purpose: create all tables, constraints, and comments of the risk review system (OLTP). Design notes: docs/oltp_design.md
-- Requires: none (reference data is loaded by oltp_seed.sql; triggers are in oltp_triggers.sql)
-- Called by: scripts/run_sql.sh source/oltp/oltp_tables.sql (run once)
-- Note: primary keys are identity columns (Trivadis G-3150); constraint names follow Trivadis: _pk / _uk / _fk / _ck;
--       table abbreviations in foreign key names are listed in docs/oltp_design.md; tables that change have created_at / updated_at
--       for timestamp-based CDC

-- ========== Users and roles ==========

create table app_user (
   user_id number generated always as identity
   , username varchar2(30) not null
   , full_name varchar2(100) not null
   , is_active varchar2(1) default 'Y' not null
   , created_at timestamp(6) default systimestamp not null
   , updated_at timestamp(6) default systimestamp not null
   , password_hash varchar2(100)
   , failed_login_count number(2) default 0 not null
   , locked_until timestamp(6)
   , password_changed_at timestamp(6)
   , constraint app_user_pk primary key (user_id)
   , constraint app_user_username_uk unique (username)
   , constraint app_user_is_active_ck check (is_active in ('Y', 'N'))
   , constraint app_user_failed_login_ck
   check (failed_login_count between 0 and 99)
);

create table app_role (
   role_id number generated always as identity
   , role_code varchar2(20) not null
   , role_name varchar2(100) not null
   , constraint app_role_pk primary key (role_id)
   , constraint app_role_role_code_uk unique (role_code)
   , constraint app_role_role_code_ck check (
      role_code in ('ANALYST', 'MANAGER')
   )
);

create table user_role (
   user_id number not null
   , role_id number not null
   , created_at timestamp(6) default systimestamp not null
   , constraint user_role_pk primary key (user_id, role_id)
   , constraint urol_usr_fk foreign key (user_id) references app_user (user_id)
   , constraint urol_rol_fk foreign key (role_id) references app_role (role_id)
);

create table user_change_event (
   event_id number generated always as identity
   , user_id number not null
   , event_at timestamp(6) default systimestamp not null
   , username varchar2(30) not null
   , full_name varchar2(100) not null
   , is_active varchar2(1) not null
   , role_list varchar2(100)
   , is_manager varchar2(1) not null
   , loaded_at timestamp(6)
   , constraint user_change_event_pk primary key (event_id)
   , constraint user_change_event_manager_ck check (is_manager in ('Y', 'N'))
);

create index user_change_event_pending_idx
on user_change_event (loaded_at, event_id);

-- ========== Review rules ==========

create table review_rule (
   rule_id number generated always as identity
   , rule_code varchar2(30) not null
   , rule_name varchar2(200) not null
   , is_active varchar2(1) default 'Y' not null
   , created_at timestamp(6) default systimestamp not null
   , updated_at timestamp(6) default systimestamp not null
   , constraint review_rule_pk primary key (rule_id)
   , constraint review_rule_rule_code_uk unique (rule_code)
   , constraint review_rule_is_active_ck check (
      is_active in ('Y', 'N')
   )
);

create table review_rule_version (
   rule_version_id number generated always as identity
   , rule_id number not null
   , version_no number not null
   , min_delinquency_status number not null
   , rule_desc varchar2(1000) not null
   , effective_from date not null
   , created_at timestamp(6) default systimestamp not null
   , constraint review_rule_version_pk primary key (rule_version_id)
   , constraint review_rule_version_no_uk unique (rule_id, version_no)
   , constraint rrv_rrl_fk foreign key (rule_id)
   references review_rule (rule_id)
   , constraint review_rule_version_min_dlq_ck check (
      min_delinquency_status between 1 and 99
   )
);



create table review_candidate (
   candidate_id number generated always as identity
   , rule_version_id number not null
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , reporting_month date not null
   , delinquency_status varchar2(3) not null
   , source_release_id varchar2(10) not null
   , created_at timestamp(6) default systimestamp not null
   , constraint review_candidate_pk primary key (candidate_id)
   , constraint review_candidate_loan_month_uk unique (
      rule_version_id, data_source, loan_identifier, reporting_month
   )
   , constraint review_candidate_data_source_ck check (
      data_source in ('FRE')
   )
   , constraint rcd_rrv_fk foreign key (rule_version_id)
   references review_rule_version (rule_version_id)
);

create table case_status (
   status_code varchar2(20) not null
   , status_name varchar2(100) not null
   , is_terminal varchar2(1) not null
   , constraint case_status_pk primary key (status_code)
   , constraint case_status_is_terminal_ck check (is_terminal in ('Y', 'N'))
);

create table case_status_transition (
   from_status varchar2(20) not null
   , to_status varchar2(20) not null
   , constraint case_status_transition_pk primary key (from_status, to_status)
   , constraint cstt_cst_from_fk foreign key (from_status)
   references case_status (status_code)
   , constraint cstt_cst_to_fk foreign key (to_status)
   references case_status (status_code)
);

create table risk_review_case (
   case_id number generated always as identity
   , case_number varchar2(20) not null
   , candidate_id number not null
   , current_status varchar2(20) default 'OPEN' not null
   , opened_by_user_id number not null
   , updated_by_user_id number not null
   , opened_at timestamp(6) default systimestamp not null
   , closed_at timestamp(6)
   , created_at timestamp(6) default systimestamp not null
   , updated_at timestamp(6) default systimestamp not null
   , constraint risk_review_case_pk primary key (case_id)
   , constraint risk_review_case_number_uk unique (case_number)
   , constraint risk_review_case_candidate_uk unique (candidate_id)
   , constraint rrc_rcd_fk foreign key (candidate_id)
   references review_candidate (candidate_id)
   , constraint rrc_cst_fk foreign key (current_status)
   references case_status (status_code)
   , constraint rrc_usr_opener_fk foreign key (opened_by_user_id)
   references app_user (user_id)
   , constraint rrc_usr_updater_fk foreign key (updated_by_user_id)
   references app_user (user_id)
);

-- Sequence for the human-readable case number RRC-000001 (Trivadis: ends in _seq)
create sequence risk_review_case_seq;

-- ========== Actions on a case (append-only, never updated) ==========

create table case_assignment (
   assignment_id number generated always as identity
   , case_id number not null
   , assignee_user_id number not null
   , assigned_by_user_id number not null
   , assigned_at timestamp(6) default systimestamp not null
   , constraint case_assignment_pk primary key (assignment_id)
   , constraint cas_rrc_fk foreign key (case_id)
   references risk_review_case (case_id)
   , constraint cas_usr_assignee_fk foreign key (assignee_user_id)
   references app_user (user_id)
   , constraint cas_usr_assigner_fk foreign key (assigned_by_user_id)
   references app_user (user_id)
);

create table case_annotation (
   annotation_id number generated always as identity
   , case_id number not null
   , author_user_id number not null
   , note_text varchar2(4000) not null
   , created_at timestamp(6) default systimestamp not null
   , updated_at timestamp(6) default systimestamp not null
   , constraint case_annotation_pk primary key (annotation_id)
   , constraint can_rrc_fk foreign key (case_id)
   references risk_review_case (case_id)
   , constraint can_usr_fk foreign key (author_user_id)
   references app_user (user_id)
);

create table case_status_history (
   status_event_id number generated always as identity
   , case_id number not null
   , from_status varchar2(20)
   , to_status varchar2(20) not null
   , changed_by_user_id number
   , changed_at timestamp(6) default systimestamp not null
   , constraint case_status_history_pk primary key (status_event_id)
   , constraint csh_rrc_fk foreign key (case_id)
   references risk_review_case (case_id)
   , constraint csh_cst_to_fk foreign key (to_status)
   references case_status (status_code)
   , constraint csh_usr_fk foreign key (changed_by_user_id)
   references app_user (user_id)
);

create table review_decision (
   decision_id number generated always as identity
   , case_id number not null
   , decision_type varchar2(20) not null
   , decided_by_user_id number not null
   , decided_as_role varchar2(20) not null
   , decision_note varchar2(4000) not null
   , decided_at timestamp(6) default systimestamp not null
   , constraint review_decision_pk primary key (decision_id)
   , constraint rdc_rrc_fk foreign key (case_id)
   references risk_review_case (case_id)
   , constraint rdc_usr_fk foreign key (decided_by_user_id)
   references app_user (user_id)
   , constraint review_decision_type_ck check (
      decision_type in ('CLOSE', 'ESCALATE', 'REOPEN')
   )
);

-- Index the foreign key columns: used when looking up assignments, notes, history, and decisions by case (Trivadis: ends in _idx)
create index cas_case_idx on case_assignment (case_id);
create index can_case_idx on case_annotation (case_id);
create index csh_case_idx on case_status_history (case_id);
create index rdc_case_idx on review_decision (case_id);

-- Table and column comments give full meanings and exceed 80 characters; line-length checks are off for this block (platform convention)
-- noqa: disable=LT05
comment on table app_user is 'OLTP: system users (analysts, managers)';
comment on column app_user.user_id is 'User ID (generated by identity)';
comment on column app_user.username is 'Login name, unique';
comment on column app_user.full_name is 'Full name';
comment on column app_user.is_active is 'Active: Y / N';
comment on column app_user.created_at is 'Creation time (for CDC)';
comment on column app_user.updated_at is 'Last modification time, maintained by trigger (for CDC)';
comment on column app_user.password_hash is 'BCrypt hash of the login password; plain text is never stored. Demo user passwords are generated randomly by scripts/11_set_demo_passwords.sh';
comment on table app_role is 'OLTP: role reference table, only ANALYST and MANAGER';
comment on column app_role.role_id is 'Role ID';
comment on column app_role.role_code is 'Role code: ANALYST / MANAGER';
comment on column app_role.role_name is 'Role name';
comment on table user_role is 'OLTP: many-to-many relation between users and roles';
comment on column user_role.user_id is 'User ID';
comment on column user_role.role_id is 'Role ID';
comment on column user_role.created_at is 'Grant time';
comment on table user_change_event is 'Full snapshot after each change of user attributes and roles; event_at is when the change happened, and CDC builds user dimension versions from it';
comment on column user_change_event.event_id is 'Event sequence number for events with the same timestamp';
comment on column user_change_event.user_id is 'ID of the changed user; no foreign key, so history of deleted users is kept';
comment on column user_change_event.event_at is 'Business change time recorded by the database, not the CDC observation time';
comment on column user_change_event.username is 'Login name after the change';
comment on column user_change_event.full_name is 'Full name after the change';
comment on column user_change_event.is_active is 'Active status after the change';
comment on column user_change_event.role_list is 'Role codes after the change';
comment on column user_change_event.is_manager is 'Manager role after the change';
comment on column user_change_event.loaded_at is 'Write-back time of the earlier sync process; the current process uses only the warehouse watermark table and no longer updates this column';
comment on table review_rule is 'OLTP: review rules (which loans enter manual review); rule parameters are in review_rule_version, and changing a rule adds a new version instead of overwriting the old one';
comment on column review_rule.rule_id is 'Rule ID';
comment on column review_rule.rule_code is 'Rule code, unique';
comment on column review_rule.rule_name is 'Rule name';
comment on column review_rule.is_active is 'Active: Y / N';
comment on column review_rule.created_at is 'Creation time (for CDC)';
comment on column review_rule.updated_at is 'Last modification time, maintained by trigger (for CDC)';
comment on table review_rule_version is 'OLTP: versions of review rules. Append-only, so every candidate can be traced to the rule parameters used at the time';
comment on column review_rule_version.rule_version_id is 'Rule version ID';
comment on column review_rule_version.rule_id is 'Rule it belongs to';
comment on column review_rule_version.version_no is 'Version number, unique within a rule';
comment on column review_rule_version.min_delinquency_status is 'Triggers when the delinquency status reaches this value (or higher, RA included); 2 means 60+ days (User Guide p.10). This is a demonstration rule, not a real bank policy';
comment on column review_rule_version.rule_desc is 'Text description of the rule';
comment on column review_rule_version.effective_from is 'Effective date';
comment on column review_rule_version.created_at is 'Creation time';
comment on table review_candidate is 'OLTP: review candidates selected from the warehouse (dwd_loan_monthly_perf) by rule. One row per rule version, loan (agency + loan number), and month. Loans are recorded by business key, not by the warehouse surrogate key (which changes on reload). When a new release corrects data, old candidates are kept and not regenerated: they record the evidence the analyst saw at the time (docs/oltp_design.md section 3)';
comment on column review_candidate.candidate_id is 'Candidate ID';
comment on column review_candidate.rule_version_id is 'Rule version that selected it';
comment on column review_candidate.data_source is 'Agency: FRE = Freddie Mac; loan numbers are assigned per agency, so agency and loan number together identify a loan';
comment on column review_candidate.loan_identifier is 'The agency''s own loan number';
comment on column review_candidate.reporting_month is 'Triggering month';
comment on column review_candidate.delinquency_status is 'Delinquency status in the triggering month (as published)';
comment on column review_candidate.source_release_id is 'Warehouse release used for selection (traceable)';
comment on column review_candidate.created_at is 'Creation time (for CDC)';
comment on table case_status is 'OLTP: case status reference table';
comment on column case_status.status_code is 'Status code';
comment on column case_status.status_name is 'Status name';
comment on column case_status.is_terminal is 'Terminal status: Y / N';
comment on table case_status_transition is 'OLTP: allowed status changes (from which status to which); the trigger rejects invalid changes based on it (DQ010)';
comment on column case_status_transition.from_status is 'Previous status';
comment on column case_status_transition.to_status is 'New status';
comment on table risk_review_case is 'OLTP: review cases. A candidate opens at most one case; status changes only as case_status_transition allows, and each change is written to case_status_history by trigger';
comment on column risk_review_case.case_id is 'Case ID (internal)';
comment on column risk_review_case.case_number is 'Human-readable case number such as RRC-000001';
comment on column risk_review_case.candidate_id is 'Candidate the case was opened from';
comment on column risk_review_case.current_status is 'Current status';
comment on column risk_review_case.opened_by_user_id is 'Who opened the case';
comment on column risk_review_case.opened_at is 'Time the case was opened';
comment on column risk_review_case.updated_by_user_id is 'Last person who changed the case; the trigger writes it to case_status_history on a status change';
comment on column risk_review_case.closed_at is 'Close time, empty if not closed';
comment on column risk_review_case.created_at is 'Creation time (for CDC)';
comment on column risk_review_case.updated_at is 'Last modification time, maintained by trigger (for CDC)';
comment on table case_assignment is 'OLTP: case assignments, append-only. The assigner must be a manager and the assignee an analyst (checked in the Java service layer)';
comment on column case_assignment.assignment_id is 'Assignment ID';
comment on column case_assignment.case_id is 'Case';
comment on column case_assignment.assignee_user_id is 'Assigned to (analyst)';
comment on column case_assignment.assigned_by_user_id is 'Assigned by (manager)';
comment on column case_assignment.assigned_at is 'Assignment time';
comment on table case_annotation is 'OLTP: notes written by analysts (reasons for the judgment)';
comment on column case_annotation.annotation_id is 'Note ID';
comment on column case_annotation.case_id is 'Case';
comment on column case_annotation.author_user_id is 'Author';
comment on column case_annotation.note_text is 'Note text';
comment on column case_annotation.created_at is 'Creation time (for CDC)';
comment on column case_annotation.updated_at is 'Last modification time, maintained by trigger (for CDC)';
comment on table case_status_history is 'OLTP: case status change history, append-only, written by trigger; records from, to, and time for every change';
comment on column case_status_history.status_event_id is 'Event ID';
comment on column case_status_history.case_id is 'Case';
comment on column case_status_history.from_status is 'Previous status; empty when the case is opened';
comment on column case_status_history.to_status is 'New status';
comment on column case_status_history.changed_by_user_id is 'Who made the change';
comment on column case_status_history.changed_at is 'Change time';
comment on table review_decision is 'OLTP: manager decisions (close, escalate, or reopen), append-only. Only managers can decide (checked in the Java service layer, verified afterwards by DQ011)';
comment on column review_decision.decision_id is 'Decision ID';
comment on column review_decision.case_id is 'Case';
comment on column review_decision.decision_type is 'CLOSE = close; ESCALATE = escalate; REOPEN = reopen';
comment on column review_decision.decided_by_user_id is 'Who decided (must be a manager)';
comment on column review_decision.decided_as_role is 'Role code written after the Java service layer verifies manager eligibility, always MANAGER; not used for historical role verification';
comment on column review_decision.decision_note is 'Reason for the decision';
comment on column review_decision.decided_at is 'Decision time';
-- noqa: enable=LT05
