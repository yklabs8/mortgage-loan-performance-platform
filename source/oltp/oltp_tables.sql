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
