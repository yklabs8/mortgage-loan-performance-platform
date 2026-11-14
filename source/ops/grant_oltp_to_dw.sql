-- Name: grant_oltp_to_dw.sql
-- Purpose: grant, table by table, the read-only OLTP access the warehouse sync procedures need.
-- Usage: ORACLE_USER=loan_oltp scripts/run_sql.sh source/ops/grant_oltp_to_dw.sql
-- Requires: the 13 loan_oltp tables exist
-- Called by: deployment of the separate OLTP schema, run by loan_oltp

grant select on review_rule to loan_dw;
grant select on review_rule_version to loan_dw;
grant select on case_status to loan_dw;
grant select on app_user to loan_dw;
grant select on app_role to loan_dw;
grant select on user_role to loan_dw;
grant select on user_change_event to loan_dw;
grant select on risk_review_case to loan_dw;
grant select on case_assignment to loan_dw;
grant select on case_status_history to loan_dw;
grant select on review_decision to loan_dw;
grant select on case_annotation to loan_dw;
grant select on review_candidate to loan_dw;
