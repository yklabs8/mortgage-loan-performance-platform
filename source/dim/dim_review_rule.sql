-- Name: dim_review_rule.sql
-- Purpose: create the review rule dimension dim_review_rule, an SCD Type 2 example: one row per rule version, with effective dates and a current flag;
--          when a rule threshold changes a new version row is added, and the old row is kept with only its end date and flag updated,
--          so one can find "which threshold version selected a candidate" and "which version was in effect on a given day"
-- Requires: none (rows are loaded by the procedure load_dim_review_rule from OLTP review_rule and review_rule_version)
-- Called by: scripts/run_sql.sh source/dim/dim_review_rule.sql (run once)

create table dim_review_rule (
   rule_version_key number generated always as identity
   , rule_version_id number not null
   , rule_id number not null
   , rule_code varchar2(30) not null
   , rule_name varchar2(200) not null
   , version_no number not null
   , min_delinquency_status number not null
   , rule_desc varchar2(1000) not null
   , valid_from date not null
   , valid_to date not null
   , is_current varchar2(1) not null
   , constraint dim_review_rule_pk primary key (rule_version_key)
   , constraint dim_review_rule_version_uk unique (rule_version_id)
   , constraint dim_review_rule_is_current_ck check (is_current in ('Y', 'N'))
   , constraint dim_review_rule_valid_ck check (valid_to >= valid_from)
);

-- noqa: disable=LT05
-- noqa: disable=LT05
comment on table dim_review_rule is 'DIM: review rule dimension, SCD Type 2, one row per version of each rule. Unlike dim_loan, a rule really changes (a real-world change), so old versions are kept with their effective ranges; release differences in dim_loan are data corrections and are not SCD2';
comment on column dim_review_rule.rule_version_key is 'Surrogate key, one per version';
comment on column dim_review_rule.rule_version_id is 'Primary key of OLTP review_rule_version (business key); review_candidate.rule_version_id joins on it';
comment on column dim_review_rule.rule_id is 'Durable key: identical for all versions of a rule (primary key of OLTP review_rule)';
comment on column dim_review_rule.rule_code is 'Rule code such as DLQ60_ENTRY; from OLTP review_rule, a change overwrites all versions (Type 1)';
comment on column dim_review_rule.rule_name is 'Rule name; as above, Type 1';
comment on column dim_review_rule.version_no is 'Version number';
comment on column dim_review_rule.min_delinquency_status is 'Threshold of this version: the delinquency status that enters review (2 = 60+ days, User Guide p.10). This is the attribute whose history SCD2 keeps';
comment on column dim_review_rule.rule_desc is 'Description of this version';
comment on column dim_review_rule.valid_from is 'Effective date (OLTP effective_from)';
comment on column dim_review_rule.valid_to is 'End date: the day before the next version takes effect; the latest version uses 9999-12-31 (a far-future date rather than null, as Kimball recommends, so "version in effect on a day" needs no null handling)';
comment on column dim_review_rule.is_current is 'Whether this is the latest version of the rule: Y / N. The latest version may not be effective yet (a new threshold entered in advance)';
-- noqa: enable=LT05
