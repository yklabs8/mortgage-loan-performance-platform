-- dq_issue.sql
-- Dq issue. See docs/metric_definitions.md for analytical definitions.
create table dq_issue (
   issue_id number generated always as identity
   , run_id number not null
   , release_id varchar2(10) not null
   , rule_id varchar2(10) not null
   , source_table varchar2(30) not null
   , source_file varchar2(100)
   , loan_identifier varchar2(50)
   , raw_period varchar2(20)
   , reason varchar2(200) not null
   , disposition varchar2(12) not null
   , constraint dq_issue_pk primary key (issue_id)
   , constraint dq_issue_run_fk foreign key (run_id) references dq_run (run_id)
   , constraint dq_issue_disposition_ck check (
      disposition in ('REJECT', 'QUARANTINE', 'WARN')
   )
);

create index dq_issue_run_ix on dq_issue (run_id, rule_id);

create table dq_quarantine (
   quarantine_id number generated always as identity
   , issue_id number not null
   , release_id varchar2(10) not null
   , source_table varchar2(30) not null
   , source_file varchar2(100) not null
   , loan_identifier varchar2(50) not null
   , raw_period varchar2(20) not null
   , rule_id varchar2(10) not null
   , reason varchar2(200) not null
   , constraint dq_quarantine_pk primary key (quarantine_id)
   , constraint dq_quarantine_issue_fk foreign key (issue_id)
   references dq_issue (issue_id)
);

create index dq_quarantine_release_ix on dq_quarantine (
   release_id, source_table
);

-- noqa: disable=LT05
comment on table dq_issue is 'Per-row ODS issues for each run; a row violating two rules has two issue records';
comment on table dq_quarantine is 'Quarantined ODS row keys, rules, and reasons. Original source rows remain in ODS.';
-- noqa: enable=LT05
