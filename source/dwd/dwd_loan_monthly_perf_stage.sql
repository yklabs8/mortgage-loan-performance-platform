-- dwd_loan_monthly_perf_stage.sql
-- Dwd loan monthly perf stage. See docs/metric_definitions.md for analytical definitions.
create table dwd_loan_monthly_perf_stage (
   loan_identifier varchar2(12)
   , monthly_reporting_period date
   , current_actual_upb number
   , current_loan_delinquency_status varchar2(3)
   , loan_age number
   , remaining_months_to_legal_maturity number
   , defect_settlement_date date
   , modification_flag varchar2(1)
   , zero_balance_code varchar2(2)
   , zero_balance_effective_date date
   , current_interest_rate number
   , current_non_interest_bearing_upb number
   , due_date_of_last_paid_installment_ddlpi date
   , mi_recoveries number
   , net_sales_proceeds varchar2(14)
   , non_mi_recoveries number
   , total_expenses number
   , legal_costs number
   , maintenance_and_preservation_costs number
   , taxes_and_insurance number
   , miscellaneous_expenses number
   , actual_loss number
   , cumulative_modification_costs number
   , interest_rate_step_indicator varchar2(1)
   , payment_deferral_flag varchar2(1)
   , estimated_loan_to_value_eltv number
   , zero_balance_removal_upb number
   , delinquent_accrued_interest number
   , delinquency_due_to_disaster varchar2(1)
   , borrower_assistance_plan varchar2(1)
   , current_period_modification_costs number
   , current_interest_bearing_upb number
   , mortgage_insurance_cancellation_indicator varchar2(1)
   , servicer_name varchar2(60)
   , bankruptcy_cramdown_costs number
   , data_source varchar2(3) not null
   , release_id varchar2(10) not null
   , loan_key number not null
   , period_date_key number(8) not null
   , servicer_key number not null
   , constraint dwd_loan_monthly_perf_stage_pk primary key (
      release_id, loan_identifier, monthly_reporting_period
   )
   , constraint dlmps_dl_fk foreign key (release_id, loan_identifier)
   references dim_loan (release_id, loan_identifier)
   , constraint dlmps_dds_fk foreign key (current_loan_delinquency_status)
   references dim_delinquency_status (status_code)
   , constraint dlmps_dzbc_fk foreign key (data_source, zero_balance_code)
   references dim_zero_balance_code (data_source, zero_balance_code)
   , constraint dlmps_dl_key_fk foreign key (loan_key)
   references dim_loan (loan_key)
   , constraint dlmps_dd_fk foreign key (period_date_key)
   references dim_date (date_key)
   , constraint dlmps_ds_fk foreign key (servicer_key)
   references dim_servicer (servicer_key)
);

-- noqa: disable=LT05
comment on table dwd_loan_monthly_perf_stage is 'DWD exchange stage. New rows are validated here before exchanging with the release partition; normally empty. Column meanings match dwd_loan_monthly_perf.';
-- noqa: enable=LT05
