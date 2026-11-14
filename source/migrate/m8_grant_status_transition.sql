-- Name: m8_grant_status_transition.sql
-- Purpose: let the warehouse quality check and the web account read the allowed OLTP status transitions.
-- Requires: loan_oltp.case_status_transition exists.
-- Called by: deployment, run by loan_oltp.

grant select on case_status_transition to loan_dw;
