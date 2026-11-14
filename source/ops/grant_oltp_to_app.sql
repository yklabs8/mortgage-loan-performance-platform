-- Name: grant_oltp_to_app.sql
-- Purpose: the OLTP owner grants the web account read access plus the minimum writes the Java review service needs.
-- Usage: ORACLE_USER=loan_oltp scripts/run_sql.sh source/ops/grant_oltp_to_app.sql
-- Requires: loan_oltp tables and review_api exist; loan_app exists
-- Called by: switching the web application to the separate OLTP schema, run by loan_oltp

grant select on app_user to loan_app;
grant select on app_role to loan_app;
grant select on user_role to loan_app;
grant select on review_rule to loan_app;
grant select on review_rule_version to loan_app;
grant select on review_candidate to loan_app;
-- Evidence is read-only; delivery registrations and stage tables are not granted.
grant select on review_evidence to loan_app;
grant select on review_evidence_month to loan_app;
grant select on risk_review_case to loan_app;
grant select on case_status to loan_app;
grant select on case_assignment to loan_app;
grant select on case_annotation to loan_app;
grant select on case_status_history to loan_app;
grant select on review_decision to loan_app;

-- The four write operations live in Java: only the target tables and two updatable case columns are granted.
grant insert on risk_review_case to loan_app;
grant insert on case_assignment to loan_app;
grant insert on case_annotation to loan_app;
grant insert on review_decision to loan_app;
grant update (current_status, updated_by_user_id) on risk_review_case
to loan_app;
-- Self-service password change and login lockout: only these four columns are opened;
-- user name, full name, and active flag still cannot be changed
grant update (
   password_hash, failed_login_count, locked_until, password_changed_at
) on app_user to loan_app;
grant select on risk_review_case_seq to loan_app;
grant select on case_status_transition to loan_app;
