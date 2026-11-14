-- Name: grant_oltp_to_test.sql
-- Purpose: let the test account read OLTP and perform the writes that the Java review service and rollback fixtures need.
-- Usage: ORACLE_USER=loan_oltp scripts/run_sql.sh source/ops/grant_oltp_to_test.sql
-- Requires: loan_oltp objects and loan_test exist
-- Called by: test setup of the split OLTP schema

grant execute on review_api to loan_test;
grant select on app_user to loan_test;
grant select on app_role to loan_test;
grant select on user_role to loan_test;
grant select on review_rule to loan_test;
grant select on review_rule_version to loan_test;
grant select on review_candidate to loan_test;
grant select on risk_review_case to loan_test;
grant select on case_status to loan_test;
grant select on case_assignment to loan_test;
grant select on case_annotation to loan_test;
grant select on case_status_history to loan_test;
grant select on review_decision to loan_test;
grant insert, update on app_user to loan_test;
grant insert on review_rule_version to loan_test;
grant insert on case_status_history to loan_test;

-- The four write operations live in Java: only the target tables and two updatable case columns are granted.
grant insert on risk_review_case to loan_test;
grant insert on case_assignment to loan_test;
grant insert on case_annotation to loan_test;
grant insert on review_decision to loan_test;
grant update (current_status, updated_by_user_id) on risk_review_case
to loan_test;
grant select on risk_review_case_seq to loan_test;
grant select on case_status_transition to loan_test;
