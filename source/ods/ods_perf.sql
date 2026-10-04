-- Name: ods_perf.sql
-- Purpose: create ODS table ods_perf: the Freddie monthly performance file (sample_perf_YYYY.txt / perf_YYYYQn.txt) landed as-is
-- Requires: user loan_dw created (scripts/1_create_db_user.sh)
-- Called by: scripts/run_sql.sh source/ods/ods_perf.sql
-- Column names, order and lengths: official Freddie Mac File Headers and File Layout (R47, July 2026 version)

-- noqa: disable=all
create table ods_perf (
   loan_identifier varchar2(12)
   , monthly_reporting_period varchar2(6)
   , current_actual_upb varchar2(12)
   , current_loan_delinquency_status varchar2(3)
   , loan_age varchar2(3)
   , remaining_months_to_legal_maturity varchar2(3)
   , underwriting_defect_and_major_servicing_defect_settlement_date varchar2(6)
   , modification_flag varchar2(1)
   , zero_balance_code varchar2(2)
   , zero_balance_effective_date varchar2(6)
   , current_interest_rate varchar2(8)
   , current_non_interest_bearing_upb varchar2(12)
   , due_date_of_last_paid_installment_ddlpi varchar2(6)
   , mi_recoveries varchar2(12)
   , net_sales_proceeds varchar2(14)
   , non_mi_recoveries varchar2(12)
   , total_expenses varchar2(12)
   , legal_costs varchar2(12)
   , maintenance_and_preservation_costs varchar2(12)
   , taxes_and_insurance varchar2(12)
   , miscellaneous_expenses varchar2(12)
   , actual_loss varchar2(12)
   , cumulative_modification_costs varchar2(12)
   , interest_rate_step_indicator varchar2(1)
   , payment_deferral_flag varchar2(1)
   , estimated_loan_to_value_eltv varchar2(4)
   , zero_balance_removal_upb varchar2(12)
   , delinquent_accrued_interest varchar2(12)
   , delinquency_due_to_disaster varchar2(1)
   , borrower_assistance_plan varchar2(1)
   , current_period_modification_costs varchar2(12)
   , current_interest_bearing_upb varchar2(12)
   , mortgage_insurance_cancellation_indicator varchar2(1)
   , servicer_name varchar2(60)
   , bankruptcy_cramdown_costs varchar2(12)
   , release_id varchar2(10) not null
   , source_file varchar2(100) not null
   , constraint ods_perf_pk primary key (
      release_id, loan_identifier, monthly_reporting_period
   )
)
partition by list (release_id, source_file) (
   partition p_default values (default)
);
-- noqa: enable=all

-- The table and column comments below spell out the official name, column position, type and maximum length,
-- so their lines exceed 80 characters; line length is not checked in this block (project convention)
-- noqa: disable=LT05
comment on table ods_perf is 'ODS: the Freddie monthly performance file (sample_perf_YYYY.txt / perf_YYYYQn.txt) landed as-is. One row per loan per month per release; primary key release_id + loan_identifier + monthly_reporting_period. All values stored as text, unchanged. Columns 1–35 follow the order of the File Layout (July 2026); the last two columns, release_id and source_file, are added by this project.';

comment on column ods_perf.loan_identifier is 'Loan Identifier | File Layout (July 2026) column 1 | Alpha Numeric - PYYQnXXXXXXX, max length 12';
comment on column ods_perf.monthly_reporting_period is 'Period | File Layout (July 2026) column 2 | Date, max length 6; the official header name is PERIOD, but period is an Oracle keyword, so the name Monthly Reporting Period from the old File Layout and the User Guide is used';
comment on column ods_perf.current_actual_upb is 'Current Actual UPB | File Layout (July 2026) column 3 | Numeric - 12,2, max length 12';
comment on column ods_perf.current_loan_delinquency_status is 'Current Loan Delinquency Status | File Layout (July 2026) column 4 | Alpha Numeric, max length 3';
comment on column ods_perf.loan_age is 'Loan Age | File Layout (July 2026) column 5 | Numeric , max length 3';
comment on column ods_perf.remaining_months_to_legal_maturity is 'Remaining Months to Legal Maturity | File Layout (July 2026) column 6 | Numeric , max length 3';
comment on column ods_perf.underwriting_defect_and_major_servicing_defect_settlement_date is 'Underwriting Defect and Major Servicing Defect Settlement Date | File Layout (July 2026) column 7 | Date, max length 6';
comment on column ods_perf.modification_flag is 'Modification Flag | File Layout (July 2026) column 8 | Alpha, max length 1';
comment on column ods_perf.zero_balance_code is 'Zero Balance Code | File Layout (July 2026) column 9 | Numeric, max length 2';
comment on column ods_perf.zero_balance_effective_date is 'Zero Balance Effective Date | File Layout (July 2026) column 10 | Date, max length 6';
comment on column ods_perf.current_interest_rate is 'Current Interest Rate | File Layout (July 2026) column 11 | Numeric - 8,3, max length 8';
comment on column ods_perf.current_non_interest_bearing_upb is 'Current Non-Interest Bearing UPB | File Layout (July 2026) column 12 | Numeric, max length 12';
comment on column ods_perf.due_date_of_last_paid_installment_ddlpi is 'Due Date of Last Paid Installment (DDLPI) | File Layout (July 2026) column 13 | Date, max length 6';
comment on column ods_perf.mi_recoveries is 'MI Recoveries | File Layout (July 2026) column 14 | Numeric - 12,2, max length 12';
comment on column ods_perf.net_sales_proceeds is 'Net Sales Proceeds | File Layout (July 2026) column 15 | Alpha-Numeric , max length 14';
comment on column ods_perf.non_mi_recoveries is 'Non MI Recoveries | File Layout (July 2026) column 16 | Numeric - 12,2, max length 12';
comment on column ods_perf.total_expenses is 'Total Expenses | File Layout (July 2026) column 17 | Numeric - 12,2, max length 12';
comment on column ods_perf.legal_costs is 'Legal Costs | File Layout (July 2026) column 18 | Numeric - 12,2, max length 12';
comment on column ods_perf.maintenance_and_preservation_costs is 'Maintenance and Preservation Costs | File Layout (July 2026) column 19 | Numeric - 12,2, max length 12';
comment on column ods_perf.taxes_and_insurance is 'Taxes and Insurance | File Layout (July 2026) column 20 | Numeric - 12,2, max length 12';
comment on column ods_perf.miscellaneous_expenses is 'Miscellaneous Expenses | File Layout (July 2026) column 21 | Numeric - 12,2, max length 12';
comment on column ods_perf.actual_loss is 'Actual Loss | File Layout (July 2026) column 22 | Numeric - 12,2, max length 12';
comment on column ods_perf.cumulative_modification_costs is 'Cumulative Modification Costs | File Layout (July 2026) column 23 | Numeric - 12,2, max length 12';
comment on column ods_perf.interest_rate_step_indicator is 'Interest Rate Step Indicator | File Layout (July 2026) column 24 | Alpha, max length 1';
comment on column ods_perf.payment_deferral_flag is 'Payment Deferral Flag | File Layout (July 2026) column 25 | Alpha, max length 1';
comment on column ods_perf.estimated_loan_to_value_eltv is 'Estimated Loan-to-Value (ELTV) | File Layout (July 2026) column 26 | Numeric, max length 4';
comment on column ods_perf.zero_balance_removal_upb is 'Zero Balance Removal UPB | File Layout (July 2026) column 27 | Numeric - 12,2, max length 12';
comment on column ods_perf.delinquent_accrued_interest is 'Delinquent Accrued Interest | File Layout (July 2026) column 28 | Numeric - 12,2, max length 12';
comment on column ods_perf.delinquency_due_to_disaster is 'Delinquency Due to Disaster | File Layout (July 2026) column 29 | Alpha, max length 1';
comment on column ods_perf.borrower_assistance_plan is 'Borrower Assistance Plan | File Layout (July 2026) column 30 | Alpha, max length 1';
comment on column ods_perf.current_period_modification_costs is 'Current Period Modification Costs | File Layout (July 2026) column 31 | Numeric - 12,2, max length 12';
comment on column ods_perf.current_interest_bearing_upb is 'Current Interest Bearing UPB | File Layout (July 2026) column 32 | Numeric - 12,2, max length 12';
comment on column ods_perf.mortgage_insurance_cancellation_indicator is 'Mortgage Insurance Cancellation Indicator | File Layout (July 2026) column 33 | Alpha, max length 1';
comment on column ods_perf.servicer_name is 'Servicer Name | File Layout (July 2026) column 34 | Alpha Numeric, max length 60';
comment on column ods_perf.bankruptcy_cramdown_costs is 'Bankruptcy Cramdown Costs | File Layout (July 2026) column 35 | Numeric - 12,2, max length 12';
comment on column ods_perf.release_id is 'Freddie data release, e.g. R47 (column added by this project; length 10 is a project convention, enough for such codes)';
comment on column ods_perf.source_file is 'Source file name; within a release, data is replaced file by file; traceable (column added by this project)';
-- noqa: enable=LT05
