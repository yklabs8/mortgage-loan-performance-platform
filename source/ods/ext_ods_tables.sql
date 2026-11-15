-- Name: ext_ods_tables.sql
-- Purpose: create external tables so Oracle can read Freddie text files from ODS_EXT_DIR (/opt/oracle/ext_data in the container).
--       Support every Freddie ODS file layout:
--       ext_ods_raw_line reads each complete line to count rows and | separators.
--                        Column-based external tables alone can discard extra columns or fill missing columns with nulls.
--       ext_ods_orig and ext_ods_perf split | fields matching ods_orig and ods_perf (new layout, R47 onward).
--       Preserve values with notrim; empty fields become null; reject limit 0 fails on any unreadable row.
--       load_ods_from_ext sets location for each input; placeholder.txt is only a placeholder.
-- Requires: ODS_EXT_DIR created and granted by scripts/3_create_ext_dir.sh.
-- Called once by scripts/2_create_ods.sh through scripts/run_sql.sh.

-- External-table clauses (organization external, access parameters) are not supported by the SQL formatter.
-- noqa: disable=all

-- Read whole lines using x'01', a delimiter absent from these input files.
create table ext_ods_raw_line (
   raw_line varchar2(4000)
)
organization external (
   type oracle_loader
   default directory ods_ext_dir
   access parameters (
      records delimited by newline characterset al32utf8
      badfile ods_ext_dir:'ext_ods_raw_line.bad'
      logfile ods_ext_dir:'ext_ods_raw_line.log'
      nodiscardfile
      fields terminated by x'01' notrim
      missing field values are null
      (raw_line char(4000))
   )
   location ('placeholder.txt')
)
reject limit 0;

-- Origination external table: 31 columns matching the names, order and lengths in ods_orig.sql.
create table ext_ods_orig (
   classic_fico varchar2(4)
   , first_payment_date varchar2(6)
   , first_time_homebuyer_indicator varchar2(1)
   , maturity_date varchar2(6)
   , metropolitan_statistical_area_msa_or_metropolitan_division varchar2(5)
   , mortgage_insurance_percentage_mi varchar2(3)
   , number_of_units varchar2(2)
   , occupancy_status varchar2(1)
   , original_combined_loan_to_value_cltv varchar2(3)
   , original_debt_to_income_dti_ratio varchar2(3)
   , original_upb varchar2(12)
   , original_loan_to_value_ltv varchar2(3)
   , original_interest_rate varchar2(6)
   , channel varchar2(1)
   , prepayment_penalty_indicator varchar2(1)
   , amortization_type varchar2(5)
   , property_state varchar2(2)
   , property_type varchar2(2)
   , postal_code varchar2(3)
   , loan_identifier varchar2(12)
   , loan_purpose varchar2(1)
   , original_loan_term varchar2(3)
   , number_of_borrowers varchar2(2)
   , seller_name varchar2(60)
   , super_conforming_flag varchar2(1)
   , pre_harp_loan_sequence_number varchar2(12)
   , special_eligibility_program varchar2(1)
   , harp_indicator varchar2(1)
   , property_valuation_method varchar2(1)
   , interest_only_i_o_indicator varchar2(1)
   , vantagescore_4_0 varchar2(4)
)
organization external (
   type oracle_loader
   default directory ods_ext_dir
   access parameters (
      records delimited by newline characterset al32utf8
      badfile ods_ext_dir:'ext_ods_orig.bad'
      logfile ods_ext_dir:'ext_ods_orig.log'
      nodiscardfile
      fields terminated by '|' notrim
      missing field values are null
   )
   location ('placeholder.txt')
)
reject limit 0;

-- Performance external table: 35 columns matching the names, order and lengths in ods_perf.sql.
create table ext_ods_perf (
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
)
organization external (
   type oracle_loader
   default directory ods_ext_dir
   access parameters (
      records delimited by newline characterset al32utf8
      badfile ods_ext_dir:'ext_ods_perf.bad'
      logfile ods_ext_dir:'ext_ods_perf.log'
      nodiscardfile
      fields terminated by '|' notrim
      missing field values are null
   )
   location ('placeholder.txt')
)
reject limit 0;
-- Names, order and lengths match ods_orig_pre202607.sql; the loader adds source metadata.
create table ext_ods_orig_pre202607 (
   credit_score varchar2(4)
   , first_payment_date varchar2(6)
   , first_time_homebuyer_flag varchar2(1)
   , maturity_date varchar2(6)
   , metropolitan_statistical_area_msa_or_metropolitan_division varchar2(5)
   , mortgage_insurance_percentage_mi varchar2(3)
   , number_of_units varchar2(2)
   , occupancy_status varchar2(1)
   , original_combined_loan_to_value_cltv varchar2(3)
   , original_debt_to_income_dti_ratio varchar2(3)
   , original_upb varchar2(12)
   , original_loan_to_value_ltv varchar2(3)
   , original_interest_rate varchar2(6)
   , channel varchar2(1)
   , prepayment_penalty_mortgage_ppm_flag varchar2(1)
   , amortization_type_formerly_product_type varchar2(5)
   , property_state varchar2(2)
   , property_type varchar2(2)
   , postal_code varchar2(5)
   , loan_sequence_number varchar2(12)
   , loan_purpose varchar2(1)
   , original_loan_term varchar2(3)
   , number_of_borrowers varchar2(2)
   , seller_name varchar2(60)
   , servicer_name varchar2(60)
   , super_conforming_flag varchar2(1)
   , pre_harp_loan_sequence_number varchar2(12)
   , program_indicator varchar2(1)
   , harp_indicator varchar2(1)
   , property_valuation_method varchar2(1)
   , interest_only_i_o_indicator varchar2(1)
   , mortgage_insurance_cancellation_indicator varchar2(1)
)
organization external (
   type oracle_loader
   default directory ods_ext_dir
   access parameters (
      records delimited by newline characterset al32utf8
      badfile ods_ext_dir:'ext_ods_orig_pre202607.bad'
      logfile ods_ext_dir:'ext_ods_orig_pre202607.log'
      nodiscardfile
      fields terminated by '|' notrim
      missing field values are null
   )
   location ('placeholder.txt')
)
reject limit 0;
-- Names, order and lengths match ods_perf_pre202607.sql; the loader adds source metadata.
create table ext_ods_perf_pre202607 (
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
)
organization external (
   type oracle_loader
   default directory ods_ext_dir
   access parameters (
      records delimited by newline characterset al32utf8
      badfile ods_ext_dir:'ext_ods_perf_pre202607.bad'
      logfile ods_ext_dir:'ext_ods_perf_pre202607.log'
      nodiscardfile
      fields terminated by '|' notrim
      missing field values are null
   )
   location ('placeholder.txt')
)
reject limit 0;
-- noqa: enable=all
