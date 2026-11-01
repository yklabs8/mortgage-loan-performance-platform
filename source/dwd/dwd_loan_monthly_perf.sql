-- dwd_loan_monthly_perf.sql
-- Dwd loan monthly perf. See docs/metric_definitions.md for analytical definitions.
-- noqa: disable=all
create table dwd_loan_monthly_perf (
   loan_identifier varchar2(12)
   , monthly_reporting_period date
   , current_actual_upb number(12, 2)
   , current_loan_delinquency_status varchar2(3)
   , loan_age number(3)
   , remaining_months_to_legal_maturity number(3)
   , defect_settlement_date date
   , modification_flag varchar2(1)
   , zero_balance_code varchar2(2)
   , zero_balance_effective_date date
   , current_interest_rate number(8, 3)
   , current_non_interest_bearing_upb number(12, 2)
   , due_date_of_last_paid_installment_ddlpi date
   , mi_recoveries number(12, 2)
   , net_sales_proceeds varchar2(14)
   , non_mi_recoveries number(12, 2)
   , total_expenses number(12, 2)
   , legal_costs number(12, 2)
   , maintenance_and_preservation_costs number(12, 2)
   , taxes_and_insurance number(12, 2)
   , miscellaneous_expenses number(12, 2)
   , actual_loss number(12, 2)
   , cumulative_modification_costs number(12, 2)
   , interest_rate_step_indicator varchar2(1)
   , payment_deferral_flag varchar2(1)
   , estimated_loan_to_value_eltv number(4)
   , zero_balance_removal_upb number(12, 2)
   , delinquent_accrued_interest number(12, 2)
   , delinquency_due_to_disaster varchar2(1)
   , borrower_assistance_plan varchar2(1)
   , current_period_modification_costs number(12, 2)
   , current_interest_bearing_upb number(12, 2)
   , mortgage_insurance_cancellation_indicator varchar2(1)
   , servicer_name varchar2(60)
   , bankruptcy_cramdown_costs number(12, 2)
   , data_source varchar2(3) not null
   , release_id varchar2(10) not null
   , loan_key number not null
   , period_date_key number(8) not null
   , servicer_key number not null
   , constraint dwd_loan_monthly_perf_pk primary key (
      release_id, loan_identifier, monthly_reporting_period
   ) using index local
   , constraint dlmp_dl_fk foreign key (release_id, loan_identifier)
   references dim_loan (release_id, loan_identifier)
   , constraint dlmp_dds_fk foreign key (current_loan_delinquency_status)
   references dim_delinquency_status (status_code)
   , constraint dlmp_dzbc_fk foreign key (data_source, zero_balance_code)
   references dim_zero_balance_code (data_source, zero_balance_code)
   , constraint dlmp_dl_key_fk foreign key (loan_key)
   references dim_loan (loan_key)
   , constraint dlmp_dd_fk foreign key (period_date_key)
   references dim_date (date_key)
   , constraint dlmp_ds_fk foreign key (servicer_key)
   references dim_servicer (servicer_key)
)
partition by list (release_id) (
   partition p_default values (default)
);
-- noqa: enable=all

-- noqa: disable=LT05
comment on table dwd_loan_monthly_perf is 'DWD: one row per release, loan, and reporting month. List-partitioned by release_id; loaded by partition exchange. Business and surrogate foreign keys reference loan, date, servicer, delinquency status, and agency-specific exit code dimensions. Source: ods_perf or ods_perf_pre202607; dates and amounts converted, codes retained.';
comment on column dwd_loan_monthly_perf.loan_identifier is 'Loan Identifier | Source: ods_perf.loan_identifier (File Layout July 2026 column 1, Alpha Numeric - PYYQnXXXXXXX) | Retain source text';
comment on column dwd_loan_monthly_perf.monthly_reporting_period is 'Period | Source: ods_perf.monthly_reporting_period (File Layout July 2026 column 2, Date) | Convert YYYYMM to the first day of that month';
comment on column dwd_loan_monthly_perf.current_actual_upb is 'Current Actual UPB | Source: ods_perf.current_actual_upb (File Layout July 2026 column 3, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.current_loan_delinquency_status is 'Current Loan Delinquency Status | Source: ods_perf.current_loan_delinquency_status (File Layout July 2026 column 4, Alpha Numeric) | Retain source text';
comment on column dwd_loan_monthly_perf.loan_age is 'Loan Age | Source: ods_perf.loan_age (File Layout July 2026 column 5, Numeric ) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.remaining_months_to_legal_maturity is 'Remaining Months to Legal Maturity | Source: ods_perf.remaining_months_to_legal_maturity (File Layout July 2026 column 6, Numeric ) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.defect_settlement_date is 'Underwriting Defect and Major Servicing Defect Settlement Date | Source: ods_perf.underwriting_defect_and_major_servicing_defect_settlement_date (File Layout July 2026 column 7, Date) | Convert YYYYMM to the first day of that month; Column name shortened to defect_settlement_date (earlier official name, Disclosure Changes v1.2 p.4)';
comment on column dwd_loan_monthly_perf.modification_flag is 'Modification Flag | Source: ods_perf.modification_flag (File Layout July 2026 column 8, Alpha) | Retain source text';
comment on column dwd_loan_monthly_perf.zero_balance_code is 'Zero Balance Code | Source: ods_perf.zero_balance_code (File Layout July 2026 column 9, Numeric) | Retain text: a code rather than an arithmetic value';
comment on column dwd_loan_monthly_perf.zero_balance_effective_date is 'Zero Balance Effective Date | Source: ods_perf.zero_balance_effective_date (File Layout July 2026 column 10, Date) | Convert YYYYMM to the first day of that month';
comment on column dwd_loan_monthly_perf.current_interest_rate is 'Current Interest Rate | Source: ods_perf.current_interest_rate (File Layout July 2026 column 11, Numeric - 8,3) | Convert text to NUMBER(8,3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.current_non_interest_bearing_upb is 'Current Non-Interest Bearing UPB | Source: ods_perf.current_non_interest_bearing_upb (File Layout July 2026 column 12, Numeric) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently; the File Layout gives no decimal places, so 12,2 follows the User Guide p.10 formula (Current Actual UPB = interest bearing + non-interest bearing UPB) and p.12 ($ Amount); real data has 12,000-18,000 rows with cents per release';
comment on column dwd_loan_monthly_perf.due_date_of_last_paid_installment_ddlpi is 'Due Date of Last Paid Installment (DDLPI) | Source: ods_perf.due_date_of_last_paid_installment_ddlpi (File Layout July 2026 column 13, Date) | Convert YYYYMM to the first day of that month';
comment on column dwd_loan_monthly_perf.mi_recoveries is 'MI Recoveries | Source: ods_perf.mi_recoveries (File Layout July 2026 column 14, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.net_sales_proceeds is 'Net Sales Proceeds | Source: ods_perf.net_sales_proceeds (File Layout July 2026 column 15, Alpha-Numeric ) | Retain source text';
comment on column dwd_loan_monthly_perf.non_mi_recoveries is 'Non MI Recoveries | Source: ods_perf.non_mi_recoveries (File Layout July 2026 column 16, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.total_expenses is 'Total Expenses | Source: ods_perf.total_expenses (File Layout July 2026 column 17, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.legal_costs is 'Legal Costs | Source: ods_perf.legal_costs (File Layout July 2026 column 18, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.maintenance_and_preservation_costs is 'Maintenance and Preservation Costs | Source: ods_perf.maintenance_and_preservation_costs (File Layout July 2026 column 19, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.taxes_and_insurance is 'Taxes and Insurance | Source: ods_perf.taxes_and_insurance (File Layout July 2026 column 20, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.miscellaneous_expenses is 'Miscellaneous Expenses | Source: ods_perf.miscellaneous_expenses (File Layout July 2026 column 21, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.actual_loss is 'Actual Loss | Source: ods_perf.actual_loss (File Layout July 2026 column 22, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.cumulative_modification_costs is 'Cumulative Modification Costs | Source: ods_perf.cumulative_modification_costs (File Layout July 2026 column 23, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.interest_rate_step_indicator is 'Interest Rate Step Indicator | Source: ods_perf.interest_rate_step_indicator (File Layout July 2026 column 24, Alpha) | Retain source text';
comment on column dwd_loan_monthly_perf.payment_deferral_flag is 'Payment Deferral Flag | Source: ods_perf.payment_deferral_flag (File Layout July 2026 column 25, Alpha) | Retain source text';
comment on column dwd_loan_monthly_perf.estimated_loan_to_value_eltv is 'Estimated Loan-to-Value (ELTV) | Source: ods_perf.estimated_loan_to_value_eltv (File Layout July 2026 column 26, Numeric) | Convert text to NUMBER(4) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.zero_balance_removal_upb is 'Zero Balance Removal UPB | Source: ods_perf.zero_balance_removal_upb (File Layout July 2026 column 27, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.delinquent_accrued_interest is 'Delinquent Accrued Interest | Source: ods_perf.delinquent_accrued_interest (File Layout July 2026 column 28, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.delinquency_due_to_disaster is 'Delinquency Due to Disaster | Source: ods_perf.delinquency_due_to_disaster (File Layout July 2026 column 29, Alpha) | Retain source text';
comment on column dwd_loan_monthly_perf.borrower_assistance_plan is 'Borrower Assistance Plan | Source: ods_perf.borrower_assistance_plan (File Layout July 2026 column 30, Alpha) | Retain source text';
comment on column dwd_loan_monthly_perf.current_period_modification_costs is 'Current Period Modification Costs | Source: ods_perf.current_period_modification_costs (File Layout July 2026 column 31, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.current_interest_bearing_upb is 'Current Interest Bearing UPB | Source: ods_perf.current_interest_bearing_upb (File Layout July 2026 column 32, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.mortgage_insurance_cancellation_indicator is 'Mortgage Insurance Cancellation Indicator | Source: ods_perf.mortgage_insurance_cancellation_indicator (File Layout July 2026 column 33, Alpha) | Retain source text';
comment on column dwd_loan_monthly_perf.servicer_name is 'Servicer Name | Source: ods_perf.servicer_name (File Layout July 2026 column 34, Alpha Numeric) | Retain source text';
comment on column dwd_loan_monthly_perf.bankruptcy_cramdown_costs is 'Bankruptcy Cramdown Costs | Source: ods_perf.bankruptcy_cramdown_costs (File Layout July 2026 column 35, Numeric - 12,2) | Convert text to NUMBER(12,2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dwd_loan_monthly_perf.data_source is 'Source agency: FRE = Freddie Mac. Paired with the zero-balance code to reference dim_zero_balance_code.';
comment on column dwd_loan_monthly_perf.release_id is 'Source data release, e.g. R47';
comment on column dwd_loan_monthly_perf.loan_key is 'Loan surrogate key looked up by release_id and loan_identifier';
comment on column dwd_loan_monthly_perf.period_date_key is 'Monthly reporting date (first of month) as integer YYYYMMDD; foreign key to dim_date';
comment on column dwd_loan_monthly_perf.servicer_key is 'Servicer surrogate key looked up by raw name; missing names map to 0';
-- noqa: enable=LT05
