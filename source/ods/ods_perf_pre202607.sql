-- Name: ods_perf_pre202607.sql
-- Purpose: create ODS table ods_perf_pre202607: the Freddie monthly performance file (old layout sample_svcg_YYYY.txt, R46 and earlier) landed as-is
-- Requires: user loan_dw created (scripts/1_create_db_user.sh)
-- Called by: scripts/run_sql.sh source/ods/ods_perf_pre202607.sql (run once)
-- Column names, order and lengths: official Freddie Mac File Layout (Pre-July 2026 version; the old layout has no official header file)

-- noqa: disable=all
create table ods_perf_pre202607 (
   loan_sequence_number varchar2(12)
   , monthly_reporting_period varchar2(6)
   , current_actual_upb varchar2(12)
   , current_loan_delinquency_status varchar2(3)
   , loan_age varchar2(3)
   , remaining_months_to_legal_maturity varchar2(3)
   , defect_settlement_date varchar2(6)
   , modification_flag varchar2(1)
   , zero_balance_code varchar2(2)
   , zero_balance_effective_date varchar2(6)
   , current_interest_rate varchar2(8)
   , current_deferred_upb varchar2(12)
   , due_date_of_last_paid_installment_ddlpi varchar2(6)
   , mi_recoveries varchar2(12)
   , net_sales_proceeds varchar2(14)
   , non_mi_recoveries varchar2(12)
   , expenses varchar2(12)
   , legal_costs varchar2(12)
   , maintenance_and_preservation_costs varchar2(12)
   , taxes_and_insurance varchar2(12)
   , miscellaneous_expenses varchar2(12)
   , actual_loss_calculation varchar2(12)
   , modification_cost varchar2(12)
   , step_modification_flag varchar2(1)
   , deferred_payment_plan varchar2(1)
   , estimated_loan_to_value_eltv varchar2(4)
   , zero_balance_removal_upb varchar2(12)
   , delinquent_accrued_interest varchar2(12)
   , delinquency_due_to_disaster varchar2(1)
   , borrower_assistance_status_code varchar2(1)
   , current_month_modification_cost varchar2(12)
   , interest_bearing_upb varchar2(12)
   , release_id varchar2(10) not null
   , source_file varchar2(100) not null
   , constraint ods_perf_pre202607_pk primary key (
      release_id, loan_sequence_number, monthly_reporting_period
   )
)
partition by list (release_id, source_file) (
   partition p_default values (default)
);
-- noqa: enable=all

-- The table and column comments below spell out the official name, column position, type and maximum length,
-- so their lines exceed 80 characters; line length is not checked in this block (project convention)
-- noqa: disable=LT05
comment on table ods_perf_pre202607 is 'ODS: the Freddie monthly performance file (old layout sample_svcg_YYYY.txt, R46 and earlier) landed as-is. Primary key release_id + loan_sequence_number + monthly_reporting_period. All values stored as text, unchanged. Columns 1–32 follow the order of the File Layout (Pre-July 2026); the last two columns, release_id and source_file, are added by this project.';
comment on column ods_perf_pre202607.loan_sequence_number is 'Loan Sequence Number | File Layout (Pre-July 2026) column 1 | Alpha Numeric - PYYQnXXXXXXX, max length 12';
comment on column ods_perf_pre202607.monthly_reporting_period is 'Monthly Reporting Period | File Layout (Pre-July 2026) column 2 | Date, max length 6';
comment on column ods_perf_pre202607.current_actual_upb is 'Current Actual UPB | File Layout (Pre-July 2026) column 3 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.current_loan_delinquency_status is 'Current Loan Delinquency Status | File Layout (Pre-July 2026) column 4 | Alpha Numeric, max length 3';
comment on column ods_perf_pre202607.loan_age is 'Loan Age | File Layout (Pre-July 2026) column 5 | Numeric , max length 3';
comment on column ods_perf_pre202607.remaining_months_to_legal_maturity is 'Remaining Months to Legal Maturity | File Layout (Pre-July 2026) column 6 | Numeric , max length 3';
comment on column ods_perf_pre202607.defect_settlement_date is 'Defect Settlement Date | File Layout (Pre-July 2026) column 7 | Date, max length 6';
comment on column ods_perf_pre202607.modification_flag is 'Modification Flag | File Layout (Pre-July 2026) column 8 | Alpha, max length 1';
comment on column ods_perf_pre202607.zero_balance_code is 'Zero Balance Code | File Layout (Pre-July 2026) column 9 | Numeric, max length 2';
comment on column ods_perf_pre202607.zero_balance_effective_date is 'Zero Balance Effective Date | File Layout (Pre-July 2026) column 10 | Date, max length 6';
comment on column ods_perf_pre202607.current_interest_rate is 'Current Interest Rate | File Layout (Pre-July 2026) column 11 | Numeric - 8,3, max length 8';
comment on column ods_perf_pre202607.current_deferred_upb is 'Current Deferred UPB | File Layout (Pre-July 2026) column 12 | Numeric, max length 12';
comment on column ods_perf_pre202607.due_date_of_last_paid_installment_ddlpi is 'Due Date of Last Paid Installment (DDLPI) | File Layout (Pre-July 2026) column 13 | Date, max length 6';
comment on column ods_perf_pre202607.mi_recoveries is 'MI Recoveries | File Layout (Pre-July 2026) column 14 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.net_sales_proceeds is 'Net Sales Proceeds | File Layout (Pre-July 2026) column 15 | Alpha-Numeric , max length 14';
comment on column ods_perf_pre202607.non_mi_recoveries is 'Non MI Recoveries | File Layout (Pre-July 2026) column 16 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.expenses is 'Expenses | File Layout (Pre-July 2026) column 17 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.legal_costs is 'Legal Costs | File Layout (Pre-July 2026) column 18 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.maintenance_and_preservation_costs is 'Maintenance and Preservation Costs | File Layout (Pre-July 2026) column 19 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.taxes_and_insurance is 'Taxes and Insurance | File Layout (Pre-July 2026) column 20 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.miscellaneous_expenses is 'Miscellaneous Expenses | File Layout (Pre-July 2026) column 21 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.actual_loss_calculation is 'Actual Loss Calculation | File Layout (Pre-July 2026) column 22 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.modification_cost is 'Modification Cost | File Layout (Pre-July 2026) column 23 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.step_modification_flag is 'Step Modification Flag | File Layout (Pre-July 2026) column 24 | Alpha, max length 1';
comment on column ods_perf_pre202607.deferred_payment_plan is 'Deferred Payment Plan | File Layout (Pre-July 2026) column 25 | Alpha, max length 1';
comment on column ods_perf_pre202607.estimated_loan_to_value_eltv is 'Estimated Loan-to-Value (ELTV) | File Layout (Pre-July 2026) column 26 | Numeric, max length 4';
comment on column ods_perf_pre202607.zero_balance_removal_upb is 'Zero Balance Removal UPB | File Layout (Pre-July 2026) column 27 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.delinquent_accrued_interest is 'Delinquent Accrued Interest | File Layout (Pre-July 2026) column 28 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.delinquency_due_to_disaster is 'Delinquency Due to Disaster | File Layout (Pre-July 2026) column 29 | Alpha, max length 1';
comment on column ods_perf_pre202607.borrower_assistance_status_code is 'Borrower Assistance Status Code | File Layout (Pre-July 2026) column 30 | Alpha, max length 1';
comment on column ods_perf_pre202607.current_month_modification_cost is 'Current Month Modification Cost | File Layout (Pre-July 2026) column 31 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.interest_bearing_upb is 'Interest Bearing UPB | File Layout (Pre-July 2026) column 32 | Numeric - 12,2, max length 12';
comment on column ods_perf_pre202607.release_id is 'Freddie data release, e.g. R46 (column added by this project; length 10 is a project convention, enough for such codes)';
comment on column ods_perf_pre202607.source_file is 'Source file name; within a release, data is replaced file by file; traceable (column added by this project)';
-- noqa: enable=LT05
