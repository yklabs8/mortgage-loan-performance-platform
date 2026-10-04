-- Name: ods_orig_pre202607.sql
-- Purpose: create ODS table ods_orig_pre202607: the Freddie origination file (old layout, R46 and earlier) landed as-is
-- Requires: user loan_dw created (scripts/1_create_db_user.sh)
-- Called by: scripts/run_sql.sh source/ods/ods_orig_pre202607.sql (run once)
-- Column names, order and lengths: official Freddie Mac File Layout (Pre-July 2026 version; the old layout has no official header file)

-- noqa: disable=all
create table ods_orig_pre202607 (
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
   , release_id varchar2(10) not null
   , source_file varchar2(100) not null
   , constraint ods_orig_pre202607_pk primary key (
      release_id, loan_sequence_number
   )
)
partition by list (release_id, source_file) (
   partition p_default values (default)
);
-- noqa: enable=all

-- The table and column comments below spell out the official name, column position, type and maximum length,
-- so their lines exceed 80 characters; line length is not checked in this block (project convention)
-- noqa: disable=LT05
comment on table ods_orig_pre202607 is 'ODS: the Freddie origination file (old layout, R46 and earlier) landed as-is. Primary key release_id + loan_sequence_number. All values stored as text, unchanged. Columns 1–32 follow the order of the File Layout (Pre-July 2026); the last two columns, release_id and source_file, are added by this project.';
comment on column ods_orig_pre202607.credit_score is 'Credit Score | File Layout (Pre-July 2026) column 1 | Numeric, max length 4';
comment on column ods_orig_pre202607.first_payment_date is 'First Payment Date | File Layout (Pre-July 2026) column 2 | Date, max length 6';
comment on column ods_orig_pre202607.first_time_homebuyer_flag is 'First Time Homebuyer Flag | File Layout (Pre-July 2026) column 3 | Alpha, max length 1';
comment on column ods_orig_pre202607.maturity_date is 'Maturity Date | File Layout (Pre-July 2026) column 4 | Date, max length 6';
comment on column ods_orig_pre202607.metropolitan_statistical_area_msa_or_metropolitan_division is 'Metropolitan Statistical Area (MSA) Or Metropolitan Division | File Layout (Pre-July 2026) column 5 | Numeric, max length 5';
comment on column ods_orig_pre202607.mortgage_insurance_percentage_mi is 'Mortgage Insurance Percentage (MI %) | File Layout (Pre-July 2026) column 6 | Numeric, max length 3';
comment on column ods_orig_pre202607.number_of_units is 'Number of Units | File Layout (Pre-July 2026) column 7 | Numeric, max length 2';
comment on column ods_orig_pre202607.occupancy_status is 'Occupancy Status | File Layout (Pre-July 2026) column 8 | Alpha, max length 1';
comment on column ods_orig_pre202607.original_combined_loan_to_value_cltv is 'Original Combined Loan-to-Value (CLTV) | File Layout (Pre-July 2026) column 9 | Numeric, max length 3';
comment on column ods_orig_pre202607.original_debt_to_income_dti_ratio is 'Original Debt-to-Income (DTI) Ratio | File Layout (Pre-July 2026) column 10 | Numeric, max length 3';
comment on column ods_orig_pre202607.original_upb is 'Original UPB | File Layout (Pre-July 2026) column 11 | Numeric, max length 12';
comment on column ods_orig_pre202607.original_loan_to_value_ltv is 'Original Loan-to-Value (LTV) | File Layout (Pre-July 2026) column 12 | Numeric, max length 3';
comment on column ods_orig_pre202607.original_interest_rate is 'Original Interest Rate | File Layout (Pre-July 2026) column 13 | Numeric - 6,3, max length 6';
comment on column ods_orig_pre202607.channel is 'Channel | File Layout (Pre-July 2026) column 14 | Alpha, max length 1';
comment on column ods_orig_pre202607.prepayment_penalty_mortgage_ppm_flag is 'Prepayment Penalty Mortgage (PPM) Flag | File Layout (Pre-July 2026) column 15 | Alpha, max length 1';
comment on column ods_orig_pre202607.amortization_type_formerly_product_type is 'Amortization Type (Formerly Product Type) | File Layout (Pre-July 2026) column 16 | Alpha, max length 5';
comment on column ods_orig_pre202607.property_state is 'Property State | File Layout (Pre-July 2026) column 17 | Alpha, max length 2';
comment on column ods_orig_pre202607.property_type is 'Property Type | File Layout (Pre-July 2026) column 18 | Alpha, max length 2';
comment on column ods_orig_pre202607.postal_code is 'Postal Code | File Layout (Pre-July 2026) column 19 | Numeric, max length 5';
comment on column ods_orig_pre202607.loan_sequence_number is 'Loan Sequence Number | File Layout (Pre-July 2026) column 20 | Alpha Numeric - PYYQnXXXXXXX, max length 12';
comment on column ods_orig_pre202607.loan_purpose is 'Loan Purpose | File Layout (Pre-July 2026) column 21 | Alpha, max length 1';
comment on column ods_orig_pre202607.original_loan_term is 'Original Loan Term | File Layout (Pre-July 2026) column 22 | Numeric, max length 3';
comment on column ods_orig_pre202607.number_of_borrowers is 'Number of Borrowers | File Layout (Pre-July 2026) column 23 | Numeric, max length 2';
comment on column ods_orig_pre202607.seller_name is 'Seller Name | File Layout (Pre-July 2026) column 24 | Alpha Numeric, max length 60';
comment on column ods_orig_pre202607.servicer_name is 'Servicer Name | File Layout (Pre-July 2026) column 25 | Alpha Numeric, max length 60';
comment on column ods_orig_pre202607.super_conforming_flag is 'Super Conforming Flag | File Layout (Pre-July 2026) column 26 | Alpha, max length 1';
comment on column ods_orig_pre202607.pre_harp_loan_sequence_number is 'Pre-HARP Loan Sequence Number | File Layout (Pre-July 2026) column 27 | Alpha Numeric - PYYQnXXXXXXX, max length 12';
comment on column ods_orig_pre202607.program_indicator is 'Program Indicator | File Layout (Pre-July 2026) column 28 | Alpha Numeric, max length 1';
comment on column ods_orig_pre202607.harp_indicator is 'HARP Indicator | File Layout (Pre-July 2026) column 29 | Alpha, max length 1';
comment on column ods_orig_pre202607.property_valuation_method is 'Property Valuation Method | File Layout (Pre-July 2026) column 30 | Numeric, max length 1';
comment on column ods_orig_pre202607.interest_only_i_o_indicator is 'Interest Only (I/O) Indicator | File Layout (Pre-July 2026) column 31 | Alpha, max length 1';
comment on column ods_orig_pre202607.mortgage_insurance_cancellation_indicator is 'Mortgage Insurance Cancellation Indicator | File Layout (Pre-July 2026) column 32 | Alpha, max length 1';
comment on column ods_orig_pre202607.release_id is 'Freddie data release, e.g. R46 (column added by this project; length 10 is a project convention, enough for such codes)';
comment on column ods_orig_pre202607.source_file is 'Source file name; within a release, data is replaced file by file; traceable (column added by this project)';
-- noqa: enable=LT05
